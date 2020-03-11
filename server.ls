require! {
    \./collector.ls : { get-transactions, start-processing }
    \body-parser
    \greenlock-express : ge
    \express
    \cors
    \./make-db-manager.ls
}

cb = console.log

err, db <- make-db-manager {}, \drive
return cb err if err?

app = express!

app.use cors!

app.get \/wallet/:address/txs , (req, res)->
    err, data <- get-transactions db, req.params.address, 100
    return res.status(400).send("#err") if err?
    res.send data

ssl = no


start-ssl = ->
    config =
        email: \some@gmail.com  
        agreeTos: yes                    
        configDir: \./.ssl/     
        communityMember: yes             
        telemetry: no
        app: app
        debug: true
    ge.create(config).listen(80, 443)

start-http = ->
    app.listen 8085
    

start-server = if ssl then start-ssl else start-http

start-server!
start-processing db