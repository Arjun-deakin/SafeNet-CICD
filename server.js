const app = require('./app');

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`SafeNet API listening on ${PORT} - server.js:4`));
