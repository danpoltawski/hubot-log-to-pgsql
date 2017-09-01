# hubot-log-to-pgsql

A hubot script that stores incoming chatroom messages to a postgresql database and provides a JSON api to retrieve the messages.

This plugin was written for a hubot implementation using the Telegram adaptor and makes some assumptions of this adaptor behaviour.

## Environment variables

### `HUBOT_LOG_ROOMS`
This environment variable contains a json structure indexed by Room ID which should be logged. Each room should contain a friendly name (which will be used to lookup messages in the JSON API and a shared secret to authenticate API requests).

```
HUBOT_LOG_ROOMS="{"#dev":{"name": "development", "secret": "@reallyS3cretStr1ng}}
```

## JSON API

Room messages can be queries at `/hubot/chatlogs/:roomname` and will be returned ordered by timestamp. The API accepts the optional parameter `aftertimestamp` which limits the results to only messages recieved after this timestamp.

See [`src/log-to-pgsql.coffee`](src/log-to-pgsql.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-log-to-pgsql --save`

Then add **hubot-log-to-pgsql** to your `external-scripts.json`:

```json
[
  "hubot-log-to-pgsql"
]
```

## NPM Module

https://www.npmjs.com/package/hubot-log-to-pgsql
