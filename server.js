const app = require('./app');

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () =>
  console.log(`SafeNet API listening on ${PORT} - server.js:5`)
);
