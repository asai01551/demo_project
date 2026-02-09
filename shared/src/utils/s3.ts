import AWS from 'aws-sdk';
import { logger } from './logger';

const s3 = new AWS.S3({
  region: process.env.AWS_REGION || 'us-east-1',
});

const bucketName = process.env.S3_BUCKET_NAME || 'webhook-relay-payloads';

export class S3Storage {
  async uploadPayload(key: string, data: any): Promise<string> {
    try {
      const params = {
        Bucket: bucketName,
        Key: key,
        Body: JSON.stringify(data),
        ContentType: 'application/json',
      };

      await s3.putObject(params).promise();
      logger.info(`Uploaded payload to S3: ${key}`);
      return key;
    } catch (error) {
      logger.error('Failed to upload to S3', { error, key });
      throw error;
    }
  }

  async getPayload(key: string): Promise<any> {
    try {
      const params = {
        Bucket: bucketName,
        Key: key,
      };

      const result = await s3.getObject(params).promise();
      return JSON.parse(result.Body?.toString() || '{}');
    } catch (error) {
      logger.error('Failed to retrieve from S3', { error, key });
      throw error;
    }
  }

  async deletePayload(key: string): Promise<void> {
    try {
      const params = {
        Bucket: bucketName,
        Key: key,
      };

      await s3.deleteObject(params).promise();
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
