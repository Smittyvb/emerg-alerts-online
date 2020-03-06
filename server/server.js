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

function parseAlertJson(alert) {
  return {
    title: Math.random(),
  }
}

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
      let alert;
      try {
        alert = await currentPSP;
      } catch (e) {
        console.log("Incomplete XML");
        return;
      }
      alert = alert.alert;
      console.log(alert, parseAlertJson(alert));
      const id = alert.identifier[0];
      alerts[id] = {
        alert: parseAlertJson(alert),
        rawXml: pendingXml,
      };
      pendingXml = "";
      console.log("ID:", id);
      sseCons.forEach(con => {
        con.socket.write("\n" + JSON.stringify({
          alert: alerts[id].alert,
        }) + "\n")
      });
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
let sseCons = [];
app.get("/api/:feedid/event-stream", (req, res) => {
  // this is called EventStream or Server-Sent Events
  const id = Math.random();
  res.status(200).set({
    Connection: "keep-alive",
    "Cache-Control": "no-cache",
    "Content-Type": "text/event-stream"
  });
  sseCons.push({
    res,
    id,
  });
  res.socket.on("close", function() {
    console.log("sse socket close");
    sseCons = sseCons.filter(con => con.id !== id);
  });
  res.write(": Connected\n");
  res.write(JSON.stringify(alerts.map(x => {alert: x.alert})) + "\n");
});
setInterval(() => {
  sseCons.forEach(con => {
    con.res.write(":");
  });
}, 8000);

app.get("/api/:feedid/search", (req, res) => {

});

app.listen(8080, () => console.log("Server started"));
