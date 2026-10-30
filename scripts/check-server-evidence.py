from pathlib import Path
import re
import stat

environment = Path('/home/devops/app/.env')
content = environment.read_text()
password = next(line.split('=', 1)[1] for line in content.splitlines() if line.startswith('POSTGRES_PASSWORD='))
assert re.fullmatch(r'[0-9a-f]{32}', password), 'Unexpected server password format'
assert stat.S_IMODE(environment.stat().st_mode) == 0o600
evidence = Path('/home/devops/devops-course-2026/evidence/practice7')
for path in evidence.iterdir():
    if path.is_file() and password.encode() in path.read_bytes():
        raise RuntimeError(f'Secret detected in evidence: {path.name}')
print('Server .env has mode 600; actual database password is absent from exported evidence.')
