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
