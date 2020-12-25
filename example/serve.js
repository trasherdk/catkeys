const clientAuthenticatedHttps = require('client-authenticated-https')

const serve = async () => {
  (await clientAuthenticatedHttps.createServer(
    { cahCheckKeyExists: true },
    (req, res) => {
      const data = []

      req.on('data', (chunk) => {
        data.push(chunk)
      })
      req.on('end', () => {
        const response = `Data received: ${data.join('')}`

        res.writeHead(200, { 'Content-Type': 'application/html' })
        res.write(response)
        res.end()
      })
    }
  )).listen(1443)
}

serve()
