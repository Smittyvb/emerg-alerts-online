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
const PER_BACKEND_FUNCS = {
  canada: {
    isHeartbeat: function(alert) {
      return alert.sender[0] === "NAADS-Heartbeat";
    },
    normalizeArchivePortion: function(str) {
      // page 24 of LMD guide
      return str
        // The minus sign (- or dash) is replaced by underscore character (_)
        .replace(/(-|-|−)/g, "_") // (there are multie types of dashes/minus signs)
        // The plus sign (+) is replaced by ‘p’ (lower case)
        .replace(/\+/g, "p")
        // The colon character (:) is replaced by underscore character (_)
        .replace(/:/g, "_");
    },
    // check if an alert is correctly signed
    checkIfAlertSigned: async function(alert) {

    },
    fetchOldAlert: async function(ref, forceBackupServer = false) {
      // page 24 of the LMD guide
      // cap-pac@canada.ca,urn:oid:2.49.0.1.124.4280542342.2020,2020-03-06T14:32:38-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.2271109197.2020,2020-03-06T14:33:38-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.2825789534.2020,2020-03-06T14:32:34-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.2654922216.2020,2020-03-06T14:32:27-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.1308899007.2020,2020-03-06T15:32:42-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.3622084484.2020,2020-03-06T15:33:17-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.2302068752.2020,2020-03-06T15:33:42-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.2627528432.2020,2020-03-06T15:34:17-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.1656974427.2020,2020-03-06T15:53:15-00:00 cap-pac@canada.ca,urn:oid:2.49.0.1.124.2963379165.2020,2020-03-06T15:53:24-00:00
      
      let [sender, id, sent] = ref.split(",");
      if (alerts[id]) {
        // already have this alert
        return [false, false];
      }

      // yes, HTTP. SSL isn't supported.
      const xmlFilename = PER_BACKEND_FUNCS.canada.normalizeArchivePortion(`${sent}I${id}`);
      const url = `http://capcp${forceBackupServer ? 2 : 1}.naad-adna.pelmorex.com/${sent.split("T")[0]}/${xmlFilename}.xml`;
      console.log(url);
      let res = await fetch(url);
      let text = await res.text();
      let json = await xml2js.parseStringPromise(text);
      return [parseAlertJson(json.alert), text];
    }
  }
};
let alerts = {};

function parseKeyvalArray(arr) {
  if (!arr) return [];
  let obj = {};
  arr.forEach(keyVal => {
    let key = keyVal.valueName[0];
    let val = keyVal.value[0];
    obj[key] = val;
  });
  return obj;
}

function parseAlertJson(alert) {
  //console.log("pAJ", alert);
  return {
    id: alert.identifier[0],
    sender: alert.sender[0],
    sent: new Date(alert.sent[0]),
    status: alert.status[0],
    msgType: alert.msgType[0],
    source: alert.source ? alert.source[0] : undefined,
    scope: alert.scope[0],
    code: alert.code || [], // multiple are allowed
    references: alert.references ? alert.references[0] : undefined,
    class: "TODO",
    addresses: alert.addresses ? alert.addresses[0] : undefined,
    restriction: alert.restriction ? alert.restriction[0] : undefined,
    note: alert.note ? alert.note[0] : undefined,
    incidents: alert.incidents ? alert.incidents[0] : undefined,
    infos: (alert.info || []).map(i => ({
      language: i.language ? i.language[0] : "en-US", // the spec says it works this way
      category: i.category[0],
      event: i.event[0],
      responseType: i.responseType ? i.responseType : undefined,
      urgency: i.urgency[0],
      severity: i.severity[0],
      certainty: i.certainty[0],
      audience: i.audience ? i.audience[0] : undefined,
      eventCodes: parseKeyvalArray(i.eventCode),
      effective: i.effective ? i.effective[0] : undefined,
      onset: i.onset ? new Date(i.onset[0]) : undefined,
      expires: i.expires ? new Date(i.expires[0]) : undefined,
      senderName: i.senderName ? new Date(i.senderName[0]) : undefined,
      headline: i.headline ? i.headline[0] : undefined,
      description: i.description ? i.description[0] : undefined,
      instruction: i.instruction ? i.instruction[0] : undefined,
      web: i.web ? i.web[0] : undefined,
      contact: i.contact ? i.contact[0] : undefined,
      parameters: parseKeyvalArray(i.parameter),
      resources: (i.resources || []).map(r => ({
        resourceDesc: r.resourceDesc[0],
        mimeType: r.mimeType[0],
        size: r.size ? r.size[0] : undefined,
        uri: r.uri ? r.uri[0] : undefined,
        derefUri: r.derefUri ? r.derefUri[0] : undefined,
        digest: r.digest ? r.digest[0] : undefined,    
      })),
      areas: [], // TODO
    })),
    signatures: [], // TODO
  };
}

function gotAlert(alert, rawXml, id, source) {
  let newAlert = false;
  if (!alerts[id]) {
    newAlert = true;
    alerts[id] = {
      alert,
      rawXml,
      confirmedFromMain: false,
      confirmedFromBackup: false,
      confirmedFromHeartbeatLink: false,
    };
  }
  if (source === "main") {
    alerts[id].confirmedFromMain = true;
  } else if (source === "backup") {
    alerts[id].confirmedFromBackup = true;
  } else if (source === "heartbeat-link") {
    alerts[id].confirmedFromHeartbeatLink = true;
  } else {
    throw new Error("invalid source " + source);
  }
  console.log("ID:", id);
  if (newAlert) {
    sseCons.forEach(con => {
      con.res.socket.write("\n" + JSON.stringify({
        alert: alerts[id].alert,
      }) + "\n")
    });
  }
}

Object.keys(TCP_API_SERVERS).forEach(key => {
  alerts[key] = [];
  TCP_API_SERVERS[key].forEach(server => {
    const socket = new net.Socket();
    let pendingXml = "";
    let currentPSP = Promise.resolve();
    socket.on("data", async data => {
      try { await currentPSP; } catch (e) {}
      let dataStr = data.toString();
      pendingXml += dataStr;
      console.log(Date.now(), "got", dataStr.length, "bytes from", server.host + ":" + server.port);
      let alert;
      try {
        // creating the promise can fail, *and* awaiting it can fail
        currentPSP = xml2js.parseStringPromise(pendingXml);
        alert = await currentPSP;
      } catch (e) {
        console.log("Incomplete XML");
        return;
      }
      alert = alert.alert;
      if (PER_BACKEND_FUNCS[key].isHeartbeat(alert)) {
        alert.references[0].split(" ").forEach(async ref => {
          // all requests are sent out concurrently
          let [json, rawXml] = await PER_BACKEND_FUNCS[key].fetchOldAlert(ref);
          if (!json) return;
          //console.log(json);
          gotAlert(json, rawXml, json.id, "heartbeat-link");
        });
      } else {
        const id = alert.identifier[0];
        let source = "main";
        if (server.host.includes("streaming2")) source = "backup";     
        gotAlert(parseAlertJson(alert), pendingXml, id, source);
        pendingXml = "";
      }
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
  res.write(JSON.stringify(Object.values(alerts)) + "\n");
});
setInterval(() => {
  sseCons.forEach(con => {
    con.res.write(":");
  });
}, 8000);

app.get("/api/:feedid/search", (req, res) => {

});

app.listen(8080, () => console.log("Server started"));