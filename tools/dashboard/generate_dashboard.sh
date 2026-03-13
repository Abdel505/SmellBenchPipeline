#!/usr/bin/env bash
set -euo pipefail

KIND=""
BENCH_DIR=""
JSON_FILE=""
OUT_HTML=""
SHA=""
TS=""
PROD=""
TEST=""
COMPARE_JSON_FILE=""
BOOTSTRAP_JSON_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) KIND="$2"; shift 2 ;;
    --bench-dir) BENCH_DIR="$2"; shift 2 ;;
    --json) JSON_FILE="$2"; shift 2 ;;
    --out) OUT_HTML="$2"; shift 2 ;;
    --sha) SHA="$2"; shift 2 ;;
    --ts) TS="$2"; shift 2 ;;
    --prod) PROD="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --compare-json) COMPARE_JSON_FILE="$2"; shift 2 ;;
    --bootstrap-json) BOOTSTRAP_JSON_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$KIND" || -z "$BENCH_DIR" || -z "$JSON_FILE" || -z "$OUT_HTML" ]]; then
  echo "[DASH][FATAL] missing args. Need --kind --bench-dir --json --out" >&2
  exit 2
fi

if [[ ! -f "$JSON_FILE" || ! -s "$JSON_FILE" ]]; then
  echo "[DASH][WARN] json missing/empty: $JSON_FILE" >&2
  exit 0
fi

TEMPLATE="tools/dashboard/template.html"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "[DASH][FATAL] missing template: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_HTML")"

# Nota: COMPARE_JSON_FILE è opzionale. Se manca o è vuoto -> placeholder diventa "{}"
KIND="$KIND" SHA="$SHA" TS="$TS" PROD="$PROD" TEST="$TEST" JSON_FILE="$JSON_FILE" COMPARE_JSON_FILE="$COMPARE_JSON_FILE" BOOTSTRAP_JSON_FILE="$BOOTSTRAP_JSON_FILE" \
perl -0777 -pe '
  use strict;
  use warnings;

  my $kind = $ENV{KIND} // "";
  my $sha  = $ENV{SHA}  // "";
  my $ts   = $ENV{TS}   // "";
  my $prod = $ENV{PROD} // "";
  my $test = $ENV{TEST} // "";
  my $json_file = $ENV{JSON_FILE} // "";
  my $cmp_file  = $ENV{COMPARE_JSON_FILE} // "";
  my $boot_file = $ENV{BOOTSTRAP_JSON_FILE} // "";

  open my $fh, "<", $json_file or die "[DASH][FATAL] cannot open json: $json_file ($!)";
  local $/;
  my $json = <$fh>;
  close $fh;

  # compare optional
  my $cmp_json = "{}";
  my $cmp_path = "";
  if ($cmp_file ne "" && -f $cmp_file && -s $cmp_file) {
    open my $ch, "<", $cmp_file or die "[DASH][FATAL] cannot open compare json: $cmp_file ($!)";
    local $/;
    $cmp_json = <$ch>;
    close $ch;
    $cmp_path = $cmp_file;
  }
  # bootstrap optional
    my $boot_json = "{}";
    my $boot_path = "";
    if ($boot_file ne "" && -f $boot_file && -s $boot_file) {
      open my $bh, "<", $boot_file or die "[DASH][FATAL] cannot open bootstrap json: $boot_file ($!)";
      local $/;
      $boot_json = <$bh>;
      close $bh;
      $boot_path = $boot_file;
    }

  # evita rotture del tag script
  $json      =~ s{</script>}{<\\/script>}gi;
  $cmp_json  =~ s{</script>}{<\\/script>}gi;
  $boot_json =~ s{</script>}{<\\/script>}gi;

  s/\@\@KIND\@\@/$kind/g;
  s/\@\@SHA\@\@/$sha/g;
  s/\@\@TS\@\@/$ts/g;
  s/\@\@PROD\@\@/$prod/g;
  s/\@\@TEST\@\@/$test/g;
  s/\@\@JSON_PATH\@\@/$json_file/g;

# compare placeholders (se non usati restano stringhe vuote o "{}")
  s/\@\@COMPARE_JSON_PATH\@\@/$cmp_path/g;
  s/\@\@COMPARE_JSON_DATA\@\@/$cmp_json/g;

  # bootstrap placeholders (se non usati restano stringhe vuote o "{}")
    s/\@\@BOOTSTRAP_JSON_PATH\@\@/$boot_path/g;
    s/\@\@BOOTSTRAP_JSON_DATA\@\@/$boot_json/g;

  # payload principale multi-line
  s/\@\@JSON_DATA\@\@/$json/g;
' "$TEMPLATE" > "$OUT_HTML"

if [[ ! -s "$OUT_HTML" ]]; then
  echo "[DASH][FATAL] generated HTML is empty: $OUT_HTML" >&2
  exit 1
fi

echo "[DASH] OK -> $OUT_HTML"
