import http from "node:http";
const server = http.createServer((req, res) => {
  res.writeHead(200, {"content-type":"application/json"});
  res.end(JSON.stringify({service:"node-demo",path:req.url,ok:true}));
});
server.listen(3000, "0.0.0.0");
