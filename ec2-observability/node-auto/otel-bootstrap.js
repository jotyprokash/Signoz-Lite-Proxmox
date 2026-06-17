'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_NAMESPACE,
  ATTR_DEPLOYMENT_ENVIRONMENT,
} = require('@opentelemetry/semantic-conventions');

const resourceAttributes = {
  [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'unknown-node-service',
};

if (process.env.OTEL_SERVICE_NAMESPACE) {
  resourceAttributes[ATTR_SERVICE_NAMESPACE] = process.env.OTEL_SERVICE_NAMESPACE;
}

if (process.env.OTEL_DEPLOYMENT_ENVIRONMENT) {
  resourceAttributes[ATTR_DEPLOYMENT_ENVIRONMENT] = process.env.OTEL_DEPLOYMENT_ENVIRONMENT;
}

const sdk = new NodeSDK({
  resource: resourceFromAttributes(resourceAttributes),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector:4317',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

const shutdown = () => {
  sdk.shutdown()
    .catch((error) => {
      console.error('OpenTelemetry shutdown error', error);
    })
    .finally(() => process.exit(0));
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

