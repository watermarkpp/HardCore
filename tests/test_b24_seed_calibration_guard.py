import hashlib,subprocess,sys
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]
@pytest.mark.parametrize('flags',[['--seed-calibrations'],['--seed-calibrations','--check'],['--seed-calibrations','--monster-id','1']])
def test_seed_entry_rejects_before_mutating_approved_authority(flags):
    paths=[ROOT/'assets/data/runtime'/name for name in ['monster_ground_contact_calibrations.json','monster_ground_contacts.json']]
    before={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    result=subprocess.run([sys.executable,str(ROOT/'tools/build_monster_ground_contacts.py'),*flags],capture_output=True,text=True,encoding='utf-8',timeout=10)
    assert result.returncode==2
    assert 'cannot' in result.stderr
    assert before=={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
