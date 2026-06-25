const moderation = require('./moderation');
const storageDataExport = require('./storage-data-export');
const auth = require('./auth');
const notifications = require('./notifications');
const feed = require('./feed');

module.exports = {
  ...moderation,
  ...storageDataExport,
  ...auth,
  ...notifications,
  ...feed
};
