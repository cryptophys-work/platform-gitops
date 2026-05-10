import importlib.util
import sys
from pathlib import Path
import pytest

# Load the module
module_name = "audit_automation_secrets"
# Use absolute path to be safe, or relative to this file
current_dir = Path(__file__).parent
file_path = current_dir / "audit_automation_secrets.py"
spec = importlib.util.spec_from_file_location(module_name, str(file_path))
if spec is None or spec.loader is None:
    raise ImportError(f"Could not load module {module_name} from {file_path}")

audit_module = importlib.util.module_from_spec(spec)
sys.modules[module_name] = audit_module
spec.loader.exec_module(audit_module)

load_text = audit_module.load_text

def test_load_text_utf8(tmp_path):
    p = tmp_path / "hello.txt"
    p.write_text("hello world\nпривет", encoding="utf-8")
    assert load_text(p) == ["hello world", "привет"]

def test_load_text_latin1_fallback(tmp_path):
    p = tmp_path / "latin1.txt"
    # 0xE9 is 'é' in latin-1, but invalid start byte in UTF-8
    content = b"H\xe9llo\n"
    p.write_bytes(content)

    # Verify it can't be decoded as utf-8 to ensure we trigger the except block
    with pytest.raises(UnicodeDecodeError):
        p.read_text(encoding="utf-8")

    # Test our function
    result = load_text(p)
    assert result == ["H\xe9llo".encode("latin-1").decode("latin-1")]
    assert result == ["Héllo"]
