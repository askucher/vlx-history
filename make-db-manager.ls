require! {
    \levelup
    \leveldown
    \prelude-ls : { obj-to-pairs, each }
    \deep-copy
    \fast-json-stable-stringify
}


memory = (config, cb)->
    get = (name, cb)->
        return cb "ReadError: get() requires a key argument" if not name?
        return cb "Not Found Record `#{name}`" if not config[name]?
        cb null, config[name]
    put = (name, value, cb)->
        config[name] = deep-copy (value ? "")
        cb null
    del = (name, cb)->
        delete config[name]
        cb null
    cb null, { get, put, del }


drive-cache = {}

make-put = (db)-> (name, v, cb)-->
    str = fast-json-stable-stringify { v }
    err, res <- db.put name, str
    return cb err if err?
    drive-cache[name] = v
    cb null, res

make-get = (db)-> (name, cb)-->
    return cb "Not Found Record `#{name}`" if not name?
    return cb null, drive-cache[name] if drive-cache[name]?
    err, data <- db.get name
    return cb err if err?
    obj = JSON.parse data.to-string(\utf8)
    drive-cache[name] = obj.v
    cb null, obj.v

init-drive = (db, [item, ...items], cb)->
    return cb null if not item?
    err <- make-put(db) item.0, item.1
    return cb err if err?
    init-drive db, items, cb

drive = (config, cb)->
    db = levelup leveldown \./db
    items =
        config
            |> obj-to-pairs
    err <- init-drive db, items
    return cb err if err?
    get = make-get db
    put = make-put db
    del = (name, cb)->
        return cb "cannot del" if not name?
        db.del name, cb
    cb null, { get, put, del }

module.exports = (config, db-type, cb)->
    return drive config, cb if db-type is \drive
    memory config, cb

  
