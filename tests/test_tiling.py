import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from phasor_core.config import default_settings, load_settings, validate_settings
from phasor_core.mango_config import render_mango_config
from phasor_core.services import Services, load_theme
from phasor_core.tiling import FIELDS, LAYOUTS


class TilingTests(unittest.TestCase):
    def test_gui_preferences_replace_native_values(self):
        settings = default_settings()
        settings['tiling'].update(layout='center_tile', innerHorizontal=17, masterRatio=.65, masterCount=2, smartGaps=True)
        result = render_mango_config(settings, 'gappih=3\ndefault_mfact=.4\nsmartgaps=0\ntagrule=id:1,layout_name:grid\n')
        self.assertEqual(result.count('gappih='), 1)
        self.assertIn('gappih=17\n', result)
        self.assertIn('default_mfact=0.65\n', result)
        self.assertIn('smartgaps=1\n', result)
        self.assertIn('tagrule=id:*,layout_name:center_tile,nmaster:2,mfact:0.65\n', result)
        self.assertNotIn('layout_name:grid', result)

    def test_old_settings_remain_valid_and_default_to_grid(self):
        settings = default_settings()
        del settings['tiling']
        validate_settings(settings)
        self.assertIn('layout_name:grid', render_mango_config(settings, ''))

    def test_invalid_preferences_are_rejected_before_save(self):
        for key, value in [('layout', 'invalid'), ('masterRatio', float('nan')), ('masterRatio', True), ('borderWidth', 13), ('innerHorizontal', -1), ('innerVertical', 3.2), ('smartGaps', 1), ('unknown', 0)]:
            with self.subTest(key=key, value=value):
                settings = default_settings()
                settings['tiling'][key] = value
                with self.assertRaises(ValueError):
                    validate_settings(settings)
        for key, (_, default, low, high) in FIELDS.items():
            if low is None:
                continue
            for boundary in (low, high):
                settings = default_settings()
                settings['tiling'][key] = boundary
                validate_settings(settings)

    def test_layouts_render_and_service_persists_then_reloads(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'runtime.conf'
            with patch.dict(os.environ, {'XDG_CONFIG_HOME': directory, 'PHASOR_MANAGED_MANGO_CONFIG': str(config)}):
                service = Services(lambda event: None)
                with patch.object(service.mango, 'reload_config', return_value={'ok': True}) as reload:
                    for layout in LAYOUTS:
                        result = service.invoke('settings.update', {'patch': {'tiling': {'layout': layout, 'outerVertical': 21}}})
                        self.assertTrue(result['sessionConfig']['reloaded'])
                        self.assertEqual(load_settings()['tiling']['layout'], layout)
                        self.assertIn(f'layout_name:{layout}', config.read_text())
                        self.assertIn('gappov=21', config.read_text())
                    self.assertEqual(reload.call_count, len(LAYOUTS))

    def test_shell_motion_uses_same_duration_as_window_manager(self):
        settings = default_settings()
        settings['spaces']['animationDuration'] = 350
        settings['appearance']['reducedMotion'] = True
        with patch('phasor_core.config.load_settings', return_value=settings):
            theme = load_theme()
        self.assertEqual(theme['animationDuration'], 350)
        self.assertTrue(theme['reducedMotion'])
        rendered = render_mango_config(settings, '')
        self.assertIn('animations=0\n', rendered)
        self.assertIn('animation_duration_move=0\n', rendered)
