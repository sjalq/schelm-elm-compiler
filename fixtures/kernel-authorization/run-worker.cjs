"use strict";

const fs = require("node:fs");
const vm = require("node:vm");

const sandbox = { console, setTimeout, clearTimeout };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

const app = sandbox.Elm.Main.init({ flags: null });
if (!app.ports || !app.ports.report) {
  throw new Error("fixture worker did not expose the report port");
}
app.ports.report.subscribe((value) => {
  console.log(value);
});
