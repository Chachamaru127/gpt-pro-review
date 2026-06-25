# manual e2e checklist

## Path A: 5.5Pro

- date:
- repo:
- project:
- command:
- request_file:
- run_id:
- browser profile:
- login setup:
- ChatGPT model:
- reply path:
- report bundle:
- summary:
- easy report:
- unresolved:

## Path B: non-5.5Pro + Tunnel

- date:
- repo:
- project:
- command:
- tunnel health:
- run_id:
- save_report result:
- reply path:
- report bundle:
- summary:
- easy report:
- finish closed exposure:
- unresolved:

## Latest smoke: Path A clean repo (2026-06-25 JST)

- repo: temporary clean fixture repo (`calc.py` zero-division bug)
- project: `gpt-pro-review-patha-live-1782320833`
- run_id: `1782320834115-915037`
- command: `scripts/pro-review-browser-run <tmp-repo> gpt-pro-review-patha-live-1782320833 --question "..."`
- browser profile: `/Users/tachibanashuuta/.pro-review/browser/profile`
- login setup: `scripts/pro-review-browser-setup --open-login` then `--mark-logged-in`; dedicated Chrome profile closed before run
- reply path: `/Users/tachibanashuuta/.pro-review/inbox/gpt-pro-review-patha-live-1782320833/REPLY-1782320834115-915037.md`
- report bundle: `/Users/tachibanashuuta/.pro-review/reports/gpt-pro-review-patha-live-1782320833/1782320834115-915037`
- summary: `total=1`, `要確認=1`, `calc.py:3` zero-division finding
- finish closed exposure: yes
- unresolved: none for Path A smoke

## Latest smoke: Path B clean repo (2026-06-25 JST)

- repo: temporary clean fixture repo (`calc.py` zero-division bug)
- project: `gpt-pro-review-pathb-live-1782321000`
- run_id: `1782321001240-edc4c5`
- command: `scripts/pro-review-run --thinking <...>` then `scripts/pro-review-tunnel-check <project>` and browser send
- tunnel health: `OK tunnel_lifecycle`, `TOOLS=search,fetch,save_report`
- save_report result: not observed
- reply path: none
- report bundle: none
- summary: none
- finish closed exposure: yes, active project cleared
- unresolved: ChatGPT chat did not have pro-review Tunnel connector tools enabled; model returned tool-unavailable text instead of calling `search` / `fetch` / `save_report`
