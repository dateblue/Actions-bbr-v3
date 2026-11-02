from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/build-extreme.yml'


class WorkflowSafetyTests(unittest.TestCase):
    def test_no_hour_long_build_on_push(self):
        s = WORKFLOW.read_text()
        marker = "if: github.event_name == 'workflow_dispatch' && inputs.build_mode == 'release'"
        self.assertIn('default: check', s)
        for name in ('Prepare kernel headers packaging',
                     'Build full ARM64 kernel DEBs (explicit release only)',
                     'Preserve built kernel DEBs immediately',
                     'Validate kernel DEB payloads',
                     'Verify pinned tcp-brutal complete module ABI',
                     'Upload separately validated Brutal module'):
            section = s.split('      - name: ' + name, 1)
            self.assertEqual(len(section), 2, name)
            self.assertIn(marker, section[1].split('      - name:', 1)[0])

    def test_module_preflight_before_kernel_and_artifact_before_post_checks(self):
        s = WORKFLOW.read_text()
        self.assertLess(s.index('Compile pinned Brutal C objects against this kernel (preflight)'),
                        s.index('Build full ARM64 kernel DEBs (explicit release only)'))
        self.assertLess(s.index('Preserve built kernel DEBs immediately'),
                        s.index('Verify pinned tcp-brutal complete module ABI'))
        self.assertIn('bash scripts/tests/test_brutal_preflight.sh', s)
        self.assertIn('if-no-files-found: error', s)


if __name__ == '__main__':
    unittest.main()
