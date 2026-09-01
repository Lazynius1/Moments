/**
 * Cloud Functions entrypoint — thin re-export layer.
 */

const registers = [
  require('./src/registers/media'),
  require('./src/registers/incognito-export'),
  require('./src/registers/triggers-engagement'),
  require('./src/registers/triggers-social'),
  require('./src/registers/triggers-messaging'),
  require('./src/registers/http-message-requests-v2'),
  require('./src/registers/triggers-cleanup'),
  require('./src/registers/http-account'),
  require('./src/registers/http-feed'),
  require('./src/registers/http-messaging'),
  require('./src/registers/http-account-batch'),
  require('./src/registers/http-auth-cleanup'),
  require('./src/registers/triggers-compliance')
];

for (const register of registers) {
  Object.assign(exports, register);
}
