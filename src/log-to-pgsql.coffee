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

userFromTelegramUser = (telegramUser) ->
    user = {}
    if telegramUser.username?
        user.username = telegramUser.username
    else
        user.username = telegramUser.id

    user.fullname = user.username
    if telegramUser.first_name?
        user.fullname = telegramUser.first_name
        user.fullname += " #{telegramUser.last_name}" if telegramUser.last_name

    return user

botuserFromTelegramAdaptor = (adaptor) ->
    user = {}
    user.username = adaptor.bot_username
    user.fullname = adaptor.bot_firstname
    return user


module.exports = (robot) ->
    database_url = process.env.LOG_DB_URL

    if !database_url?
        throw new Error('LOG_DB_URL is not set.')

    if !process.env.LOG_ROOMS?
        throw new Error('LOG_ROOMS is not set.')

    rooms_by_id = JSON.parse process.env.LOG_ROOMS
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
            robot.logger.info "log-to-pgsql starting logging on #{roomdata['name']} (#{roomdata['id']})}"



    client = new Postgres.Client(database_url)
    client.connect()
    client.query "CREATE TABLE IF NOT EXISTS chatlogs (messageid serial, room text, username text, fullname text, message text, timestamp timestamptz(3) default current_timestamp)"
    client.query "CREATE INDEX IF NOT EXISTS idx_time_room ON chatlogs (timestamp, room)"
    robot.logger.debug "log-to-pgsql connected to #{database_url}."

    insertLogEntry = (room, user, message) ->
        if !rooms_by_id[room]
            robot.logger.info "log-to-pgsql ignoring message in room #{room}"
            return

        robot.logger.info "log-to-pgsql logging message to #{room}"
        client.query "INSERT INTO chatlogs (room, username, fullname, message) VALUES ($1, $2, $3, $4)", [
            room,
            user.username,
            user.fullname,
            message,
        ]

    # Log recieved room messages..
    robot.receiveMiddleware (context, next, done) ->
        return if !context.response.message.text?

        user = userFromTelegramUser context.response.message.user
        insertLogEntry context.response.envelope.room, user, context.response.message.text
        next(done)

    # Log messages sent from the bot..
    robot.responseMiddleware (context, next, done) ->
        return unless context.plaintext?

        user = botuserFromTelegramAdaptor context.response.robot.adapter
        insertLogEntry context.response.envelope.room, user, context.strings.join('/n')
        next(done)

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
        if req.query.aftertimestamp
            wheresql = "#{wheresql} AND timestamp > $2"
            params.push req.query.aftertimestamp

        # 10,0000 results, to set a limit, but won't be the normal case..
        sql = "SELECT messageid, username, fullname, message, timestamp
                FROM chatlogs
                #{wheresql}
                ORDER BY timestamp LIMIT 10000"

        client.query sql, params, (err, result) ->
            if err
                res.status(500).send('Internal error')
                robot.logger.error 'Error querying chatlogs', err
                return
            else
                json = JSON.stringify(result.rows);
                res.writeHead(200, {'content-type': 'application/json', 'content-length': Buffer.byteLength(json)}); 
                res.end(json);

