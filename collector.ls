require! {
    \ws : Ws
    \./math.ls : { plus, minus, times, div }
    \prelude-ls : { find }
}

#process.env['NODE_TLS_REJECT_UNAUTHORIZED'] = 0

#body =
#  #perMessageDeflate: false
#  #origin : "https://explorer.velas.com"

ws = new Ws \ws://188.165.206.165:8094/ws
 
ws.on \open , ->
  console.log \open

#{"id":"-1","cmd":4,"params":{"header":{"hash":"879aedc314ef651e4826178724ed94f58f414cf6043b0d43037ffae74b5c8673","prev_block":"fc50cf00561e3f6640f3dd6ef5801924b02fd2dd4d03b10eeb50f579bcd2ea25","merkle_root":"bf989b9c4c15ae1dc054c8bce1330d7d52ba5622e9d48f84e81a2896e803af80","script":"5f529d0c822afcea74ce5b50d6629b200b1c2f3be92c0d621aa013dfd5e7f0cb35d3d1c18eb0eaf3c426059af5f9454f5752cf70c592def126db178f51ec6801","seed":"9655597ea9e8fd207ea2bb8a8bdba2ea64e4839cf788c8126ad798d1f6f93cdf","type":1,"height":745564,"size":1925,"version":1,"timestamp":1578407601,"bits":0,"nonce":0,"txn_count":2,"advice_count":0},"txns":[{"hash":"e41dd12450ccc4aa14c222c6c9906fa396517c37f4161daf3fb4ad4281be7f4e","version":1,"lock_time":0,"tx_in":[{"signature_script":"","wallet_address":"","previous_output":{"hash":"ddbe8265788769ae5733c97e5c08eb2a7114ccac568373f684f0bd1e2535802c","index":0,"value":100000},"sequence":1}],"tx_out":[{"pk_script":"0ff40d477cc8eb116136208af56cca1cf012d9e97f8d50831d7b","wallet_address":"VLLYcezxg9pq2FGPvFWz9ErTP8DSLVR1cFc","node_id":"0000000000000000000000000000000000000000000000000000000000000000","index":0,"value":100000,"payload":null}]},{"hash":"ddbe8265788769ae5733c97e5c08eb2a7114ccac568373f684f0bd1e2535802c","version":1,"lock_time":0,"tx_in":[{"signature_script":"ff782d495247098f23614f361ca7010d5315d32923c8bb2450390dc48456ad58fa6e0e0d8df1e7ae23ec387657a6c294341cf846041542b5aa5329cb708d160a","wallet_address":"VLUFpSAZcryeBSfrfTT7BbjygouMWXeDXsY","previous_output":{"hash":"fc50cf00561e3f6640f3dd6ef5801924b02fd2dd4d03b10eeb50f579bcd2ea25","index":0,"value":10147133434},"sequence":0,"public_key":"stKSEwheFS7HUv+H8aYcupUjmXv7yQIefQikAeMWWa8="}],"tx_out":[{"pk_script":"","node_id":"0000000000000000000000000000000000000000000000000000000000000000","index":0,"value":100000,"payload":null},{"pk_script":"0ff40d477cc8eb116136208af56cca1cf012d9e97f8d50831d7b","wallet_address":"VLLYcezxg9pq2FGPvFWz9ErTP8DSLVR1cFc","node_id":"0000000000000000000000000000000000000000000000000000000000000000","index":1,"value":10147033434,"payload":null}]}],"advices":null}}

json-parse = (data, cb)->
    try
        cb null, JSON.parse(data)
    catch err
        cb err

decimals = 5

humanize = (value)->
    value `div` (10^decimals)

store-one = (db, type, parent, tx, cb)->
    { wallet_address, value } = tx
    #console.log { tx, parent } if not wallet_address?
    #TODO: get fee
    return cb null if not wallet_address?
    #console.log \store, wallet_address
    err, balance-guess <- db.get "/wallet/#{wallet_address}"
    balance = 
        | err? => 0
        | _ => balance-guess
    #console.log tx if typeof! value isnt \Number
    return cb "expected value for IN transaction" if typeof! value isnt \Number and type is \IN
    sent-value =
        | type is \IN => humanize(value)
        | type is \OUT => humanize(tx.previous_output.value)
        | _ => 0
    new-balance =
        | type is \IN => balance `plus` sent-value
        | type is \OUT => balance `minus` sent-value
        | _ => balance
    err <- db.put "/wallet/#{wallet_address}", new-balance
    return cb err if err?
    err, index-guess <- db.get "/wallet/#{wallet_address}/txs/last-index"
    index =
        | err? => 0
        | _ => index-guess `plus` 1
    err <- db.put "/wallet/#{wallet_address}/txs/last-index", index
    return cb err if err?

    amount = humanize sent-value
    another-tx =
        | type is \IN => parent.tx_in |> find (-> it.wallet_address?)
        | _ => parent.tx_out |> find (-> it.wallet_address?)
    fee-tx =
        | type is \IN => parent.tx_in |> find (-> not it.wallet_address?)
        | _ => parent.tx_out |> find (-> not it.wallet_address?)
    fee = 
        | fee-tx? => humanize fee-tx.value
        | _ => 0
    time = 0
    url = "https://explorer.velas.com/tnx/#{parent.hash}"
    from =
        | type is \IN => another-tx.wallet_address
        | _ => wallet_address
    to =
        | type is \IN => wallet_address
        | _ => another-tx.wallet_address
    err <- db.put "/wallet/#{wallet_address}/txs/#{index}", { tx: parent.hash, amount, fee, time, url, from, to }
    return cb err if err?
    cb null

load-transactions = (db, wallet_address, index, cb)->
    return cb null, [] if index < 0
    err, tx <- db.get "/wallet/#{wallet_address}/txs/#{index}"
    return cb err if err?
    next-index = index `minus` 1
    <- set-immediate
    err, txs <- load-transactions db, wallet_address, next-index
    return cb err if err?
    all = [tx] ++ txs
    cb null, all

export get-transactions = (db, wallet_address, limit, cb)->
    return cb "expected limit -> number" if typeof! limit isnt \Number
    return cb null, [] if limit is 0
    err, index-guess <- db.get "/wallet/#{wallet_address}/txs/last-index"
    return cb null, [] if err?
    index = index-guess ? 0
    latest = 
        | limit < index => limit
        | _ => index
    #console.log { latest }
    load-transactions db, wallet_address, latest, cb
    
    

store-each = (db, type, parent, [tx, ...txs], cb)->
    return cb null if not tx?
    
    err <- store-one db, type, parent, tx
    return cb err if err?
    
    <- set-immediate
    store-each db, type, parent, txs, cb



store = (db, type, parent, txs, cb)->
    return cb "expected array, got #{typeof! txs}" if typeof! txs isnt \Array
    store-each db, type, parent, txs, cb
    
    

process-each-tx = (db, [tx, ...txs], cb)->
    return cb null if not tx?
    err <- store db, 'OUT', tx, tx.tx_in
    return cb err if err?
    err <- store db, 'IN', tx, tx.tx_out
    return cb err if err?
    <- set-immediate
    process-each-tx db, txs, cb

process-message = (db)-> (data)->
    cb = console.log
    return if typeof! data isnt \String
    err, message <- json-parse data
    return cb err if err?
    return cb "expected id -1 and cmd 4" if message.id isnt "-1" and message.cmd isnt 4
    return cb "expected array got #{JSON.stringify message}" if typeof! message.params?txns isnt \Array
    txns = message.params.txns
    process-each-tx db, txns, cb
    

export start-processing = (db)->
    ws.on \message , process-message(db)
