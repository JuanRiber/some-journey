import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/profile/profile_models.dart';

/// # Editar perfil — escolher como se apresentar.
///
/// **Por que existe:** o Perfil é identidade. Foto, @username e uma frase são o
/// que transforma uma conta em uma PESSOA dentro do Some Journey.
///
/// **O que o usuário sente:** cuidado, não formulário. Três campos, a foto em
/// destaque, e o @ com as regras explicadas ANTES do erro.
///
/// **Ação principal:** salvar. A foto salva sozinha ao ser escolhida (é o gesto
/// mais direto: escolheu, virou seu avatar).
///
/// **Atrito:** nada é obrigatório. Quem não quer @username simplesmente não
/// escolhe um — e o app segue mostrando as iniciais.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.identity.name);
  late final TextEditingController _username =
      TextEditingController(text: widget.profile.identity.username ?? '');
  late final TextEditingController _bio =
      TextEditingController(text: widget.profile.identity.bio ?? '');

  late Profile _profile = widget.profile;
  bool _saving = false;
  bool _uploading = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = '';
      _saving = true;
    });
    try {
      final username = _username.text.trim();
      final updated = await Api.instance.updateProfile(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        // String vazia significa "não mexer": limpar o @ é outra operação, e
        // mandar "" seria recusado pelas regras de formato.
        username: username.isEmpty ? null : username,
        bio: _bio.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      // 422 (formato/reservado) e 409 (em uso) já vêm com mensagem pronta.
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível salvar agora.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Reduz ANTES de enviar: avatar não precisa de 12 MP, e o teto do backend
      // é 5 MB. Menos rede para o usuário, menos custo de storage.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _error = '';
      _uploading = true;
    });
    try {
      final bytes = await picked.readAsBytes();
      final updated = await Api.instance.setAvatar(
        bytes,
        picked.name,
        picked.mimeType ?? 'image/jpeg',
      );
      if (mounted) setState(() => _profile = updated);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível enviar a foto.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _uploading = true);
    try {
      final updated = await Api.instance.removeAvatar();
      if (mounted) setState(() => _profile = updated);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final identity = _profile.identity;
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: SJSpace.screenX,
            right: SJSpace.screenX,
            top: SJSpace.x2,
            bottom: SJSpace.x12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Voltar',
                  // Devolve o perfil possivelmente atualizado pela foto, mesmo
                  // sem salvar os campos — o avatar já foi persistido.
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(_profile),
                    icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: SJSpace.x4),
              const SJOverline('Sua identidade'),
              const SizedBox(height: SJSpace.x2),
              Text('Editar perfil', style: SJText.h1(color: s.ink)),
              const SizedBox(height: SJSpace.x8),
              _avatarBlock(s, identity),
              const SizedBox(height: SJSpace.x8),
              SJTextField(label: 'Nome', controller: _name, hint: 'Como quer ser chamado'),
              const SizedBox(height: SJSpace.x4),
              SJTextField(
                label: 'Nome de usuário',
                controller: _username,
                hint: 'seuarroba',
                // Prefixo constante: o @ é do produto, não algo a digitar.
                trailing: Text('@', style: SJText.body(color: s.inkFaint)),
              ),
              const SizedBox(height: SJSpace.x2),
              // Regras ANTES do erro: evita a frustração de descobrir no envio.
              Text(
                'Letras, números e _ , começando por letra. De 3 a 30 caracteres.',
                style: SJText.caption(color: s.inkFaint),
              ),
              const SizedBox(height: SJSpace.x4),
              SJTextField(
                label: 'Sua frase',
                controller: _bio,
                hint: 'Cada lugar guarda uma história.',
                maxLines: 3,
                minLines: 2,
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: SJSpace.x4),
                Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: SJText.caption(color: s.danger),
                ),
              ],
              const SizedBox(height: SJSpace.x6),
              SJButton(
                label: 'Salvar',
                loading: _saving,
                expand: true,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarBlock(SJScheme s, ProfileIdentity identity) => Column(
        children: [
          Semantics(
            button: true,
            label: 'Trocar foto de perfil',
            child: SJPressable(
              onTap: _uploading ? null : _pickAvatar,
              child: Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: s.surfaceAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.frame, width: 2),
                  image: identity.avatarUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(identity.avatarUrl!),
                          fit: BoxFit.cover,
                        ),
                ),
                alignment: Alignment.center,
                child: _uploading
                    ? const SJSpinner()
                    : identity.avatarUrl != null
                        ? null
                        : Text(identity.initials, style: SJText.h1(color: s.accent)),
              ),
            ),
          ),
          const SizedBox(height: SJSpace.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SJButton(
                label: identity.avatarUrl == null ? 'Escolher foto' : 'Trocar foto',
                variant: SJButtonVariant.text,
                onPressed: _uploading ? null : _pickAvatar,
              ),
              if (identity.avatarUrl != null)
                SJButton(
                  label: 'Remover',
                  variant: SJButtonVariant.text,
                  onPressed: _uploading ? null : _removeAvatar,
                ),
            ],
          ),
        ],
      );
}
