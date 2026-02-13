import AWS from 'aws-sdk';
import { logger } from './logger';

let s3: AWS.S3 | null = null;
let bucketName: string;

function getS3Client(): AWS.S3 {
  if (!s3) {
    // Configure AWS SDK globally
    AWS.config.update({
      region: process.env.AWS_REGION || 'us-east-1',
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    });
    
    s3 = new AWS.S3();
    bucketName = process.env.S3_BUCKET_NAME || 'webhook-relay-payloads';
    
    logger.info('S3 client initialized', {
      region: process.env.AWS_REGION,
      bucket: bucketName,
      hasAccessKey: !!process.env.AWS_ACCESS_KEY_ID,
    });
  }
  return s3;
}

export class S3Storage {
  async uploadPayload(key: string, data: any): Promise<string> {
    try {
      const client = getS3Client();
      const params = {
        Bucket: bucketName,
        Key: key,
        Body: JSON.stringify(data),
        ContentType: 'application/json',
      };

      await client.putObject(params).promise();
      logger.info(`Uploaded payload to S3: ${key}`);
      return key;
    } catch (error) {
      logger.error('Failed to upload to S3', { error, key });
      throw error;
    }
  }

  async getPayload(key: string): Promise<any> {
    try {
      const client = getS3Client();
      const params = {
        Bucket: bucketName,
        Key: key,
      };

      const result = await client.getObject(params).promise();
      return JSON.parse(result.Body?.toString() || '{}');
    } catch (error) {
      logger.error('Failed to retrieve from S3', { error, key });
      throw error;
    }
  }

  async deletePayload(key: string): Promise<void> {
    try {
      const client = getS3Client();
      const params = {
        Bucket: bucketName,
        Key: key,
      };

      await client.deleteObject(params).promise();
      logger.info(`Deleted payload from S3: ${key}`);
    } catch (error) {
      logger.error('Failed to delete from S3', { error, key });
      throw error;
    }
  }

  generateKey(prefix: string, id: string): string {
    const date = new Date().toISOString().split('T')[0];
    return `${prefix}/${date}/${id}.json`;
  }
}

export const s3Storage = new S3Storage();

// Made with Bob
