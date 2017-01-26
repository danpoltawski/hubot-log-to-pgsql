# Description
#   A hubot script that stores to logs to pgsql
#
# Configuration:
#   LOG_DB_URL
#   LOG_ROOMS
#
# Notes:
#   The restrictions on log access are not designe to be only protection.
#
# Author:
#   Dan Poltawski <dan@moodle.com>
Postgres = require 'pg'

module.exports = (robot) ->
    database_url = process.env.LOG_DB_URL
    rooms_by_id = JSON.parse process.env.LOG_ROOMS

    if !database_url?
        throw new Error('LOG_DB_URL is not set.')

    if !rooms_by_id?
        throw new Error('LOG_ROOMS is not set.')

    if !Object.keys(rooms_by_id).length
        throw new Error('LOG_ROOMS is empty')

    rooms_by_name = {}
    for roomid, roomdata of rooms_by_id
        throw new Error("LOG_ROOMS invalid") if !roomid
        throw new Error("LOG_ROOMS invalid, name not set for room '#{roomid}'") if !roomdata['name']
        throw new Error("LOG_ROOMS invalid, secret not for room '#{roomid}'") if !roomdata['secret']
        if rooms_by_name[roomdata['name']]
            throw new Error("LOG_ROOMS invalid, duplicate room name '#{roomdata['name']}'")
        else
            roomdata['id'] = roomid;
            rooms_by_name[roomdata['name']] = roomdata


    client = new Postgres.Client(database_url)
    client.connect()
    client.query "CREATE TABLE IF NOT EXISTS chatlogs (messageid serial, room text, userfrom text, message text, timestamp timestamptz default current_timestamp)"
    client.query "CREATE INDEX IF NOT EXISTS idx_query ON chatlogs (messageid, room)"
    robot.logger.debug "log-to-pgsql connected to #{database_url}."

    robot.hear /(.+)/i, (msg) ->
        return if !msg.message.text || !msg.message.room
        return if !rooms_by_id[msg.message.room]
        robot.logger.debug "log-to-pgsql logging message to #{msg.message.room}"
        client.query "INSERT INTO chatlogs (room, userfrom, message) VALUES ($1, $2, $3)", [
            msg.message.room,
            msg.message.user.username,
            msg.message.text,
        ]

    robot.router.post '/hubot/chatlogs/:roomname', (req, res) ->
        room = req.params.roomname
        roomconfig = rooms_by_name[room]
        data = if req.body.payload? then JSON.parse req.body.payload else req.body

        if !roomconfig
            res.status(404).send('Not found.')
            return

        if !data.secret
            res.status(400).send('Bad request')
            return

        if data.secret != roomconfig['secret']
            res.status(403).send('Forbidden')
            return

        wheresql = "WHERE room = $1"
        params = [roomconfig["id"]]
        if req.query.aftermessageid
            wheresql = "#{wheresql} AND messageid > $2"
            params.push req.query.aftermessageid

        # 10,0000 results, to set a limit, but won't be the normal case..
        sql = "SELECT messageid, userfrom, message, timestamp
                FROM chatlogs
                #{wheresql}
                ORDER BY messageid LIMIT 10000"

        client.query sql, params, (err, result) ->
            if err
                res.status(500).send('Internal error')
                robot.logger.error 'Error querying chatlogs', err
                return
            else
                json = JSON.stringify(result.rows);
                res.writeHead(200, {'content-type': 'application/json', 'content-length': Buffer.byteLength(json)}); 
                res.end(json);

