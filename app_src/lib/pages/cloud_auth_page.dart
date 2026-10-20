import 'package:flutter/material.dart';
import '../state.dart';

/// 登录页（独立页面）
class CloudLoginPage extends StatefulWidget {
  final AppState state;
  const CloudLoginPage({super.key, required this.state});
  @override
  State<CloudLoginPage> createState() => _CloudLoginPageState();
}

class _CloudLoginPageState extends State<CloudLoginPage> {
  final emailCtl = TextEditingController();
  final pwCtl = TextEditingController();
  bool busy = false;
  String? err;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 02 账号')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('登录后使用官方免费模型「02」',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 20),
          TextField(
            controller: emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱', border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pwCtl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码', border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          if (err != null) ...[
            const SizedBox(height: 12),
            Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy ? null : doLogin,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(busy ? '登录中…' : '登录'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => CloudRegisterPage(state: widget.state))),
            child: const Text('没有账号？注册'),
          ),
        ]),
      ),
    );
  }

  Future<void> doLogin() async {
    setState(() { busy = true; err = null; });
    try {
      final r = await widget.state.cloudPost('/api/auth/login', {
        'email': emailCtl.text.trim(),
        'password': pwCtl.text,
      });
      if (r['status'] == 200 && r['data']['access'] != null) {
        await widget.state.setCloudAuth(
          token: r['data']['access'],
          email: r['data']['email'] ?? emailCtl.text.trim(),
          refresh: r['data']['refresh'] ?? '',
        );
        await widget.state.refreshCloud();
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => err = r['data']['error'] ?? '登录失败');
      }
    } catch (e) {
      setState(() => err = '网络错误：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// 注册页（独立页面）
class CloudRegisterPage extends StatefulWidget {
  final AppState state;
  const CloudRegisterPage({super.key, required this.state});
  @override
  State<CloudRegisterPage> createState() => _CloudRegisterPageState();
}

class _CloudRegisterPageState extends State<CloudRegisterPage> {
  final emailCtl = TextEditingController();
  final pwCtl = TextEditingController();
  final sqCtl = TextEditingController();
  final saCtl = TextEditingController();
  bool busy = false;
  String? err;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册 02 账号')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('注册后永久登录，每 5 小时 3000 万 token + 10 张图免费',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 20),
          TextField(
            controller: emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱', border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pwCtl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码（至少 6 位）', border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: sqCtl,
            decoration: const InputDecoration(
              labelText: '安全问题（例如：我小学叫什么？）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.help_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: saCtl,
            decoration: const InputDecoration(
              labelText: '安全问题答案（忘密码时用来找回）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.security),
            ),
          ),
          if (err != null) ...[
            const SizedBox(height: 12),
            Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy ? null : doRegister,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(busy ? '注册中…' : '注册并登录'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => CloudLoginPage(state: widget.state))),
            child: const Text('已有账号？登录'),
          ),
        ]),
      ),
    );
  }

  Future<void> doRegister() async {
    if (pwCtl.text.length < 6) {
      setState(() => err = '密码至少 6 位');
      return;
    }
    if (sqCtl.text.trim().isEmpty || saCtl.text.trim().isEmpty) {
      setState(() => err = '请填写安全问题和答案');
      return;
    }
    setState(() { busy = true; err = null; });
    try {
      final r = await widget.state.cloudPost('/api/auth/register', {
        'email': emailCtl.text.trim(),
        'password': pwCtl.text,
        'security_q': sqCtl.text.trim(),
        'security_a': saCtl.text.trim(),
      });
      if (r['status'] == 200 && r['data']['access'] != null) {
        await widget.state.setCloudAuth(
          token: r['data']['access'],
          email: r['data']['email'] ?? emailCtl.text.trim(),
          refresh: r['data']['refresh'] ?? '',
        );
        await widget.state.refreshCloud();
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => err = r['data']['error'] ?? '注册失败');
      }
    } catch (e) {
      setState(() => err = '网络错误：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
