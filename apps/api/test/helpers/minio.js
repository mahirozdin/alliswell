import { S3Client, CreateBucketCommand } from '@aws-sdk/client-s3';

/**
 * MinIO plumbing for the storage integration tests (ATTACHMENTS.md §12).
 *
 * Defaults line up with docker-compose (`docker compose up -d minio`) AND the
 * CI `docker run` step — override with real STORAGE_S3_* env to point at
 * something else. The bucket is created here, with retries, so neither compose
 * nor CI needs init-container choreography: the first test run IS the init.
 */
export function storageTestEnv(env = process.env) {
  return {
    STORAGE_S3_ENDPOINT: env.STORAGE_S3_ENDPOINT ?? 'http://127.0.0.1:9000',
    STORAGE_S3_BUCKET: env.STORAGE_S3_BUCKET ?? 'alliswell',
    STORAGE_S3_ACCESS_KEY_ID: env.STORAGE_S3_ACCESS_KEY_ID ?? 'alliswell',
    STORAGE_S3_SECRET_ACCESS_KEY: env.STORAGE_S3_SECRET_ACCESS_KEY ?? 'alliswell_dev',
  };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Creates the bucket if it does not exist yet, retrying while MinIO boots
 * (CI starts the container seconds before the suite reaches this).
 */
export async function ensureBucket(storageConfig, { attempts = 40, delayMs = 500 } = {}) {
  const client = new S3Client({
    endpoint: storageConfig.endpoint,
    region: storageConfig.region,
    forcePathStyle: storageConfig.forcePathStyle,
    credentials: {
      accessKeyId: storageConfig.accessKeyId,
      secretAccessKey: storageConfig.secretAccessKey,
    },
  });
  try {
    for (let attempt = 1; ; attempt += 1) {
      try {
        await client.send(new CreateBucketCommand({ Bucket: storageConfig.bucket }));
        return;
      } catch (err) {
        if (err?.name === 'BucketAlreadyOwnedByYou' || err?.name === 'BucketAlreadyExists') {
          return; // a previous run created it — exactly what we want
        }
        if (attempt >= attempts) throw err;
        await sleep(delayMs); // MinIO still booting (ECONNREFUSED et al.)
      }
    }
  } finally {
    client.destroy();
  }
}
