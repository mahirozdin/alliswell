import fp from 'fastify-plugin';

/**
 * Core's outgoing mail (OPH-406, ADR-0064) — `app.mailer`.
 *
 * `null` when this server has no SMTP block, for the reason `app.pushTransport`
 * is: "can this server send mail?" must be a value a caller checks, not a call
 * that quietly does nothing. The forgot form answers `delivery: "admin"` then.
 *
 * A test (or a caller with its own transport) passes `mailer` to `buildApp`;
 * anything with `send({ to, subject, text })` will do.
 *
 * nodemailer is imported only when a block is configured, so an install with
 * no mail never loads it.
 */
export default fp(
  async function mailPlugin(app, { mailer } = {}) {
    // `app.mailQueue` — work that leads to a mail and must not hold up the
    // answer (the forgot form: whether an account exists must not show in its
    // response time). `defer` runs it after the current request; `idle`
    // resolves once nothing deferred is left; closing the server waits for it,
    // so a shutdown does not cut a lookup or a send in half.
    const pending = new Set();
    app.decorate('mailQueue', {
      /** @param {() => Promise<unknown>} work @param {(err: Error) => void} onError */
      defer(work, onError) {
        const job = Promise.resolve()
          .then(work)
          .catch(onError)
          .finally(() => pending.delete(job));
        pending.add(job);
      },
      async idle() {
        while (pending.size > 0) await Promise.allSettled([...pending]);
      },
    });
    app.addHook('onClose', async () => app.mailQueue.idle());

    if (mailer !== undefined) {
      app.decorate('mailer', mailer);
      return;
    }
    const { smtp } = app.config.mail;
    if (!smtp.host) {
      app.decorate('mailer', null);
      return;
    }
    const { default: nodemailer } = await import('nodemailer');
    const transport = nodemailer.createTransport({
      host: smtp.host,
      port: smtp.port,
      secure: smtp.secure,
      ...(smtp.user ? { auth: { user: smtp.user, pass: smtp.password } } : {}),
    });
    app.log.info({ host: smtp.host, port: smtp.port }, 'mail transport ready');
    app.decorate('mailer', {
      async send({ to, subject, text }) {
        await transport.sendMail({ from: smtp.from, to, subject, text });
      },
    });
    app.addHook('onClose', async () => transport.close());
  },
  { name: 'alliswell-mail' },
);
