const express  = require("express");
const fetch    = require("node-fetch");
const net      = require("net");
const xml2js   = require("xml2js");

const USER_AGENT = "online-emerg-alert-fetcher/0.1";
const TCP_API_SERVERS = {
  canada: [
    {
      host: "streaming1.naad-adna.pelmorex.com",
      port: 8080,
      name: "AlertReady Oakville server",
    }, {
      host: "streaming2.naad-adna.pelmorex.com",
      port: 8080,
      name: "AlertReady Montreal server",
    }
  ]
};
let alerts = {};
Object.keys(TCP_API_SERVERS).forEach(key => {
  alerts[key] = [];
  TCP_API_SERVERS[key].forEach(server => {
    const socket = new net.Socket();
    let pendingXml = "";
    let currentPSP = Promise.resolve();
    socket.on("data", async data => {
      await currentPSP;
      let dataStr = data.toString();
      pendingXml += dataStr;
      console.log(Date.now(), "got", dataStr.length, "bytes from", server.host + ":" + server.port);
      currentPSP = xml2js.parseStringPromise(pendingXml);
      let xml;
      try {
        xml = await currentPSP;
      } catch (e) {
        console.log("Incomplete XML");
        return;
      }
      pendingXml = "";
      const id = alert.$.identifier[0];
      alerts[id] = xml;
    });
    socket.on("connect", () => {
      console.log("Streaming", key, "alerts from", server.host + ":" + server.port);
    });
    socket.connect({
      port: server.port,
      host: server.host,
    });
  });
});

const app = express();
app.get("/api/:feedid/event-stream", (req, res) => {

});
app.get("/api/:feedid/search", (req, res) => {

});

app.listen(8080, () => console.log("Server started"));
