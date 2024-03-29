Host = require './host'
RemoteFile = require './remote-file'
LocalFile = require './local-file'

fs = require 'fs-plus'
ssh2 = require 'ssh2'
async = require 'async'
util = require 'util'
filesize = require 'file-size'
moment = require 'moment'
Serializable = require 'serializable'
Path = require 'path'
osenv = require 'osenv'
_ = require 'underscore-plus'

module.exports =
  class SftpHost extends Host
    Serializable.includeInto(this)
    atom.deserializers.add(this)

    Host.registerDeserializers(SftpHost)

    connection: undefined
    protocol: "sftp"

    constructor: (@alias = null, @hostname, @directory, @username, @port = "22", @localFiles = [], @usePassword = false, @useAgent = true, @usePrivateKey = false, @password, @passphrase, @privateKeyPath) ->
      super( @alias, @hostname, @directory, @username, @port, @localFiles, @usePassword)

    getConnectionStringUsingAgent: ->
      connectionString =  {
        host: @hostname,
        port: @port,
        username: @username,
      }

      if atom.config.get('remote-edit.agentToUse') != 'Default'
        _.extend(connectionString, {agent: atom.config.get('remote-edit.agentToUse')})
      else if process.platform == "win32"
        _.extend(connectionString, {agent: 'pageant'})
      else
        _.extend(connectionString, {agent: process.env['SSH_AUTH_SOCK']})

      connectionString

    getConnectionStringUsingKey: ->
      return {
        host: @hostname,
        port: @port,
        username: @username,
        privateKey: @getPrivateKey(@privateKeyPath),
        passphrase: @passphrase
      }

    getConnectionStringUsingPassword: ->
      return {
        host: @hostname,
        port: @port,
        username: @username,
        password: @password
      }

    getPrivateKey: (path) ->
      if path[0] == "~"
        path = Path.normalize(osenv.home() + path.substring(1, path.length))

      return fs.readFileSync(path, 'ascii', (err, data) ->
        throw err if err?
        return data.trim()
      )

    createRemoteFileFromFile: (path, file) ->
      remoteFile = new RemoteFile(Path.normalize("#{path}/#{file.filename}").split(Path.sep).join('/'), (file.longname[0] != 'd'), (file.longname[0] == 'd'), filesize(file.attrs.size).human(), parseInt(file.attrs.mode, 10).toString(8).substr(2, 4), moment(file.attrs.mtime * 1000).format("HH:MM DD/MM/YYYY"))
      return remoteFile


    ####################
    # Overridden methods
    getConnectionString: (connectionOptions) ->
      if @useAgent
        return _.extend(@getConnectionStringUsingAgent(), connectionOptions)
      else if @usePrivateKey
        return _.extend(@getConnectionStringUsingKey(), connectionOptions)
      else if @usePassword
        return _.extend(@getConnectionStringUsingPassword(), connectionOptions)
      else
        throw new Error("No valid connection method is set for SftpHost!")

    close: (callback) ->
      @connection?.end()
      callback?(null)

    connect: (callback, connectionOptions = {}) ->
      @emitter.emit 'info', {message: "Connecting to sftp://#{@username}@#{@hostname}:#{@port}", className: 'text-info'}
      async.waterfall([
        (callback) =>
          if @usePrivateKey
            fs.exists(@privateKeyPath, ((exists) =>
              if exists
                callback(null)
              else
                @emitter.emit 'info', {message: "Private key does not exist!", className: 'text-error'}
                callback(new Error("Private key does not exist"))
              )
            )
          else
            callback(null)
        (callback) =>
          @connection = new ssh2()
          @connection.on 'error', (err) =>
            @emitter.emit 'info', {message: "Error occured when connecting to sftp://#{@username}@#{@hostname}:#{@port}", className: 'text-error'}
            @connection.end()
            callback(err)
          @connection.on 'ready', =>
            @emitter.emit 'info', {message: "Successfully connected to sftp://#{@username}@#{@hostname}:#{@port}", className: 'text-success'}
            callback(null)
          @connection.connect(@getConnectionString(connectionOptions))
      ], (err) ->
        callback?(err)
      )

    isConnected: ->
      @connection? and @connection._state == 'authenticated'

    writeFile: (file, text, callback) ->
      @emitter.emit 'info', {message: "Writing remote file sftp://#{@username}@#{@hostname}:#{@port}#{file.remoteFile.path}", className: 'text-info'}
      async.waterfall([
        (callback) =>
          @connection.sftp(callback)
        (sftp, callback) ->
          sftp.fastPut(file.path, file.remoteFile.path, callback)
      ], (err) =>
        if err?
          @emitter.emit('info', {message: "Error occured when writing remote file sftp://#{@username}@#{@hostname}:#{@port}#{file.remoteFile.path}", className: 'text-error'})
          console.error err if err?
        else
          @emitter.emit('info', {message: "Successfully wrote remote file sftp://#{@username}@#{@hostname}:#{@port}#{file.remoteFile.path}", className: 'text-success'})
        @close()
        callback?(err)
      )


    getFilesMetadata: (path, callback) ->
      async.waterfall([
        (callback) =>
          @connection.sftp(callback)
        (sftp, callback) ->
          sftp.readdir(path, callback)
        (files, callback) =>
          async.map(files, ((file, callback) => callback(null, @createRemoteFileFromFile(path, file))), callback)
        (objects, callback) ->
          objects.push(new RemoteFile((path + "/.."), false, true, null, null, null))
          objects.push(new RemoteFile((path + "/."), false, true, null, null, null))
          if atom.config.get 'remote-edit.showHiddenFiles'
            callback(null, objects)
          else
            async.filter(objects, ((item, callback) -> item.isHidden(callback)), ((result) -> callback(null, result)))
      ], (err, result) =>
        if err?
          @emitter.emit('info', {message: "Error occured when reading remote directory sftp://#{@username}@#{@hostname}:#{@port}:#{path}", className: 'text-error'} )
          console.error err if err?
          callback?(err)
        else
          callback?(err, (result.sort (a, b) -> return if a.name.toLowerCase() >= b.name.toLowerCase() then 1 else -1))
      )

    getFileData: (file, callback) ->
      @emitter.emit('info', {message: "Getting remote file sftp://#{@username}@#{@hostname}:#{@port}#{file.path}", className: 'text-info'})
      async.waterfall([
        (callback) =>
          @connection.sftp(callback)
        (sftp, callback) ->
          s = sftp.createReadStream(file.path)
          data = []
          s.on 'data', ((d) -> data.push(d.toString()))
          s.on 'error', ((error) ->
            e = new Error("ENOENT, open #{file.path}")
            callback?(e)
          )
          s.on 'close', (-> callback(null, data.join('')))
      ], (err, result) =>
        @emitter.emit('info', {message: "Error when reading remote file sftp://#{@username}@#{@hostname}:#{@port}#{file.path}", className: 'text-error'}) if err?
        @emitter.emit('info', {message: "Successfully read remote file sftp://#{@username}@#{@hostname}:#{@port}#{file.path}", className: 'text-success'}) if !err?
        callback?(err, result)
      )

    serializeParams: ->
      {
        @alias
        @hostname
        @directory
        @username
        @port
        localFiles: JSON.stringify(localFile.serialize() for localFile in @localFiles)
        @useAgent
        @usePrivateKey
        @usePassword
        @password
        @passphrase
        @privateKeyPath
      }

    deserializeParams: (params) ->
      tmpArray = []
      for localFile in JSON.parse(params.localFiles)
        localFileDeserialized = LocalFile.deserialize(localFile)
        tmpArray.push(localFileDeserialized)

      params.localFiles = tmpArray
      params
