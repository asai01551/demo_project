export interface WebhookPayload {
  id: string;
  endpointId: string;
  method: string;
  headers: Record<string, string>;
  body: any;
  receivedAt: Date;
}

export interface DeliveryResult {
  success: boolean;
  statusCode?: number;
  responseBody?: any;
  errorMessage?: string;
  duration: number;
}

export interface RetryConfig {
  maxAttempts: number;
  delayMs: number;
  backoffMultiplier: number;
}

export interface QueueMessage {
  type: 'webhook' | 'retry';
  eventId: string;
  endpointId: string;
  destinationUrl: string;
  payloadS3Key: string;
  attemptNumber: number;
  headers?: Record<string, string>;
}

export interface EndpointConfig {
  id: string;
  userId: string;
  name: string;
  destinationUrl: string;
  secret?: string;
  isActive: boolean;
}

export interface WebhookEventStatus {
  id: string;
  status: 'pending' | 'forwarding' | 'delivered' | 'failed';
  receivedAt: Date;
  forwardedAt?: Date;
  attempts: number;
}

// Made with Bob
