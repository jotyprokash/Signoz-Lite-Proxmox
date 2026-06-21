'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { resourceFromAttributes } = require('@opentelemetry/resources');

const resourceAttributes = {
  'service.name': process.env.OTEL_SERVICE_NAME || 'unknown-node-service',
};
const ignoredHttpPaths = new Set(
  (process.env.OTEL_NODE_IGNORED_PATHS || '/health,/ready,/live,/metrics')
    .split(',')
    .map((path) => path.trim())
    .filter(Boolean),
);

if (process.env.OTEL_SERVICE_NAMESPACE) {
  resourceAttributes['service.namespace'] = process.env.OTEL_SERVICE_NAMESPACE;
}

if (process.env.OTEL_DEPLOYMENT_ENVIRONMENT) {
  resourceAttributes['deployment.environment.name'] = process.env.OTEL_DEPLOYMENT_ENVIRONMENT;
  resourceAttributes['deployment.environment'] = process.env.OTEL_DEPLOYMENT_ENVIRONMENT;
}

const sdk = new NodeSDK({
  resource: resourceFromAttributes(resourceAttributes),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector:4317',
  }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-dns': { enabled: false },
    '@opentelemetry/instrumentation-fs': { enabled: false },
    '@opentelemetry/instrumentation-express': { enabled: false },
    '@opentelemetry/instrumentation-http': {
      ignoreIncomingRequestHook: (request) => {
        const requestPath = (request.url || '').split('?', 1)[0];
        return ignoredHttpPaths.has(requestPath);
      },
    },
  })],
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
