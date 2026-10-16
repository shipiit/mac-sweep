#!/usr/bin/env python3
"""Apply the versioned branch rules without changing repository visibility."""
import json
from pathlib import Path
import subprocess
import sys

REPOSITORY = 'shipiit/mac-sweep'
ROOT = Path(__file__).resolve().parents[1]


def api(endpoint, method='GET', payload=None):
    args = ['gh', 'api', endpoint, '--method', method]
    if payload is not None:
        args += ['--input', '-']
    result = subprocess.run(args, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True)
    if result.returncode:
        sys.exit(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout) if result.stdout.strip() else None


def main():
    repo = api(f'repos/{REPOSITORY}')
    if repo['private']:
        sys.exit('No rules changed: this repository is private. GitHub Free requires a public repository for these rules; a suitable paid plan also supports private repositories. This script never changes visibility.')
    existing = {item['name']: item['id'] for item in api(f'repos/{REPOSITORY}/rulesets?includes_parents=false')}
    for path in sorted((ROOT / '.github/rulesets').glob('*.json')):
        desired = json.loads(path.read_text())
        rule_id = existing.get(desired['name'])
        endpoint = f'repos/{REPOSITORY}/rulesets' + (f'/{rule_id}' if rule_id else '')
        saved = api(endpoint, 'PUT' if rule_id else 'POST', desired)
        verified = api(f'repos/{REPOSITORY}/rulesets/{saved["id"]}')
        for field in ('enforcement', 'conditions', 'bypass_actors', 'rules'):
            if verified[field] != desired[field]:
                sys.exit(f'Verification mismatch in {desired["name"]}: {field}. Inspect repository rules before proceeding.')
        print(f'Active and verified: {verified["name"]} ({verified["id"]})')
    for branch in ('main', 'master'):
        rules = api(f'repos/{REPOSITORY}/rules/branches/{branch}')
        print(f'{branch}: ' + ', '.join(sorted({rule['type'] for rule in rules})))


if __name__ == '__main__':
    main()
