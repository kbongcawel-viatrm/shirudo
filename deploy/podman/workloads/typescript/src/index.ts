import { createServer } from "node:http";
createServer((_req, res) => {
  res.writeHead(200, {"content-type":"application/json"});
  res.end(JSON.stringify({service:"typescript-demo",ok:true}));
}).listen(3001, "0.0.0.0");
