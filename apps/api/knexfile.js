import { loadConfig } from './src/config.js';
import { buildKnexConfig } from './src/db/knexconfig.js';

const config = loadConfig();

export default buildKnexConfig(config);
