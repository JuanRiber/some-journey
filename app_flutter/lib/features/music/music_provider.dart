/// # Música — contrato de PROVEDOR (Adapter Pattern).
///
/// Uma memória pode ter música: a canção que estava tocando naquele lugar é
/// parte da lembrança. Mas o CATÁLOGO é um detalhe de infraestrutura, não do
/// domínio — por isso o app conversa com esta interface, nunca com um serviço
/// concreto.
///
/// ## Decisão arquitetural (por que uma interface, e por que iTunes primeiro)
/// - **Apple Music / MusicKit** (1ª preferência do produto) exige conta paga de
///   desenvolvedor Apple e um developer token JWT assinado com chave privada —
///   inviável sem credencial e impossível de embutir no cliente com segurança.
/// - **Spotify** exige OAuth com client *secret*; o segredo NÃO pode viver no
///   app, então precisaria de um proxy no nosso backend antes de existir.
/// - **iTunes Search API** (implementada agora): catálogo da PRÓPRIA Apple,
///   gratuita, SEM chave, funciona no web e no nativo, e devolve tudo que a UI
///   precisa — capa, álbum, duração, prévia de 30s e link para ouvir.
///
/// Trocar de provedor = escrever outra classe que implemente [MusicProvider] e
/// mudar UMA linha na composição. Nada na UI nem no domínio muda.
library;

/// Uma faixa, no vocabulário do NOSSO domínio (não no do provedor).
///
/// É um DTO imutável: o adapter traduz o JSON de quem quer que seja para cá, e o
/// resto do app só conhece este formato. `externalId` + `provider` identificam a
/// origem, permitindo reabrir/ressincronizar a faixa depois.
class MusicTrack {
  const MusicTrack({
    required this.provider,
    required this.externalId,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.previewUrl,
    this.externalUrl,
    this.durationMs,
  });

  /// Identificador do provedor de origem ('itunes', 'spotify', 'deezer'...).
  final String provider;

  /// Id da faixa NO provedor (para reabrir/atualizar depois).
  final String externalId;

  final String title;
  final String artist;
  final String? album;

  /// Capa do álbum (a UI amplia: os provedores costumam servir miniaturas).
  final String? artworkUrl;

  /// Prévia curta (30s). Guardada para um player interno futuro.
  final String? previewUrl;

  /// Link para ouvir a faixa completa no serviço.
  final String? externalUrl;

  final int? durationMs;

  /// "3:42" — duração legível; vazio quando o provedor não informa.
  String get durationLabel {
    final ms = durationMs;
    if (ms == null || ms <= 0) return '';
    final total = ms ~/ 1000;
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Forma de persistência (e de tráfego para o backend). As chaves usam
  /// snake_case para casar com o contrato da API.
  Map<String, dynamic> toJson() => {
        'provider': provider,
        'external_id': externalId,
        'title': title,
        'artist': artist,
        'album': album,
        'artwork_url': artworkUrl,
        'preview_url': previewUrl,
        'external_url': externalUrl,
        'duration_ms': durationMs,
      };

  factory MusicTrack.fromJson(Map<String, dynamic> j) => MusicTrack(
        provider: (j['provider'] ?? 'itunes') as String,
        externalId: (j['external_id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        album: j['album'] as String?,
        artworkUrl: j['artwork_url'] as String?,
        previewUrl: j['preview_url'] as String?,
        externalUrl: j['external_url'] as String?,
        durationMs: (j['duration_ms'] as num?)?.toInt(),
      );

  /// Duas faixas são a mesma quando vêm do mesmo provedor com o mesmo id —
  /// usado para não anexar a mesma música duas vezes à memória.
  @override
  bool operator ==(Object other) =>
      other is MusicTrack &&
      other.provider == provider &&
      other.externalId == externalId;

  @override
  int get hashCode => Object.hash(provider, externalId);
}

/// Erro de busca de música. A UI mostra uma mensagem calma e segue — música é
/// um enfeite da memória, nunca um bloqueio para registrá-la.
class MusicSearchError implements Exception {
  MusicSearchError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// O contrato. Qualquer catálogo (iTunes, Apple Music, Spotify, Deezer) entra no
/// app implementando SÓ isto.
abstract interface class MusicProvider {
  /// Nome curto do provedor (vai gravado na faixa).
  String get id;

  /// Busca faixas por texto livre (nome, artista, álbum).
  ///
  /// Deve devolver lista vazia para consulta vazia/curta, e levantar
  /// [MusicSearchError] em falha de rede/resposta — nunca vazar exceções cruas
  /// de transporte para a camada de UI.
  Future<List<MusicTrack>> search(String query, {int limit});
}
