import closeWithGrace from 'close-with-grace';
import { buildApp } from './app.js';

const app = await buildApp();

const closeListeners = closeWithGrace({ delay: 10000 }, async ({ err }) => {
  if (err) app.log.error({ err }, 'shutting down due to error');
  await app.close();
});

app.addHook('onClose', (_instance, done) => {
  closeListeners.uninstall();
  done();
});

try {
  await app.listen({ host: app.config.host, port: app.config.port });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
