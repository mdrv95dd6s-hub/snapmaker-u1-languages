// Generator skryptu instalacyjnego. Używany przez stronę i przez test w node.
// Wymaga zmiennych: TPL (szablon), DATA = { "pl-PL": {main:"base64gzip", exc:"base64gzip"}, ... }
function wrap76(s) { return s.replace(/(.{76})/g, "$1\n").replace(/\n$/, ""); }
function buildScript(opts, TPL, DATA, withData) {
  const langs = opts.langs.filter(l => DATA[l]);
  let files = "";
  if (opts.mode === "install") {
    for (const l of langs) {
      files += `cat > "$T/${l}.json.b64" <<'B64'\n${withData ? wrap76(DATA[l].main) : "(…dane tłumaczenia…)"}\nB64\n`;
      files += `cat > "$T/exception_${l}.json.b64" <<'B64'\n${withData ? wrap76(DATA[l].exc) : "(…dane tłumaczenia…)"}\nB64\n`;
    }
  }
  const body = TPL.replace("@@MODE@@", opts.mode).replace("@@LANGS@@", langs.join(" "))
    .replace("@@ACTIVE@@", opts.active || "").replace("@@HIDE@@", opts.hide === false ? "no" : "yes").replace("@@FILES@@", files.replace(/\$/g, "$$$$"));
  if (!withData) return body;
  return "cat > /tmp/u1lang.sh <<'U1_EOF'\n" + body + "\nU1_EOF\nsh /tmp/u1lang.sh </dev/null; rc=$?; rm -f /tmp/u1lang.sh; exit $rc\n";
}
if (typeof module !== "undefined") module.exports = { buildScript };
