# -*- coding: utf-8 -*-
import re

base = '/home/user/Doubao/chats/38445728458548482/repo-tmp/app_src/lib/'

def sub_file(path, pairs):
    src = open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert old in src, f'{path}: NOT FOUND: {old[:60]}'
        src = src.replace(old, new)
    open(path, 'w', encoding='utf-8').write(src)
    print('patched:', path)

# local_models_page.dart（已由首次运行完成，跳过）
print('skip local_models_page (done in first run)')

# state.dart
sub_file(base + 'state.dart', [
    ("ts: (msg['ts'] as num? ?? 0).toDouble()));",
     "ts: (msg['ts'] is num ? msg['ts'] as num : 0).toDouble()));"),
    ("providers = (config['providers'] ?? []) as List;",
     "providers = (config['providers'] is List ? config['providers'] as List : []);"),
    ("models = (config['models'] ?? []) as List;",
     "models = (config['models'] is List ? config['models'] as List : []);"),
    ("conversations = (config['conversations'] ?? []) as List;",
     "conversations = (config['conversations'] is List ? config['conversations'] as List : []);"),
])

# chat_page.dart
sub_file(base + 'pages/chat_page.dart', [
    ("final results = (r['results'] as List<dynamic>? ?? [])",
     "final results = (r['results'] is List ? r['results'] as List<dynamic> : <dynamic>[])"),
    ("final custom = (state.settings['prompts'] as List<dynamic>? ?? [])",
     "final custom = (state.settings['prompts'] is List ? state.settings['prompts'] as List<dynamic> : <dynamic>[])"),
    ("final list = (state.settings['prompts'] as List<dynamic>? ?? [])",
     "final list = (state.settings['prompts'] is List ? state.settings['prompts'] as List<dynamic> : <dynamic>[])"),
])

# plugins_page.dart
sub_file(base + 'pages/plugins_page.dart', [
    ("return (r['plugins'] as List? ?? [])",
     "return (r['plugins'] is List ? r['plugins'] as List : <dynamic>[])"),
    ("final tools = (plugin['tools'] as List? ?? [])",
     "final tools = (plugin['tools'] is List ? plugin['tools'] as List : <dynamic>[])"),
])

# add_model_dialog.dart
sub_file(base + 'dialogs/add_model_dialog.dart', [
    ("if (err != null && (r['models'] as List? ?? []).isEmpty)",
     "if (err != null && (r['models'] is List ? (r['models'] as List).isEmpty : true))"),
    ("_fetched = (r['models'] as List)",
     "_fetched = (r['models'] is List ? r['models'] as List : <dynamic>[])"),
])

print('ALL DONE')
