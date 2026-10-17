"""Compatibility entry for the stronger pinned-source extraction/owner gate."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
raise SystemExit(subprocess.call([sys.executable,str(ROOT/'tests/physics_exact_source_test.py'),'--engine','C:/Users/Administrator/Documents/HardCore-engine-v115/godot','--output',str(ROOT/'outputs/v115_multicore/physics_exact_rework/SOURCE_EQUIVALENCE.json')]))
