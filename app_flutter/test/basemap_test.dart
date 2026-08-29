// A cor da base cartográfica.
//
// Este teste existe por um erro que eu cometi e que a tela não denunciou: a
// rampa saiu INVERTIDA — o branco da telha virava sépia escuro e o traço virava
// creme. Um mapa em negativo não parece "cor errada", parece "o mapa sumiu", e
// custa muito tempo até alguém desconfiar da matriz.
//
// Aqui a afirmação é em CORES, não em coeficientes: o branco do OpenStreetMap
// tem de virar papel; o traço, sépia. E no modo escuro, o oposto exato.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/basemap.dart';

/// Quão longe duas cores estão, por canal. Comparar cor com `==` seria frágil:
/// um erro de arredondamento de 1/255 não é um defeito.
int _distancia(Color a, Color b) {
  final dr = ((a.r - b.r) * 255).abs();
  final dg = ((a.g - b.g) * 255).abs();
  final db = ((a.b - b.b) * 255).abs();
  return [dr, dg, db].reduce((x, y) => x > y ? x : y).round();
}

Matcher _pertoDe(Color esperada, {int tolerancia = 3}) => predicate<Color>(
      (c) => _distancia(c, esperada) <= tolerancia,
      'perto de #${esperada.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    );

void main() {
  const branco = Color(0xFFFFFFFF);
  const preto = Color(0xFF000000);

  group('papel quente (modo claro)', () {
    final m = SJBasemap.matrizClara;

    test('o branco da telha vira papel', () {
      expect(SJBasemap.aplicar(m, branco), _pertoDe(const Color(0xFFF7F2E7)));
    });

    test('o traço escuro vira couro', () {
      expect(SJBasemap.aplicar(m, preto), _pertoDe(const Color(0xFF6B5540)));
    });

    test('NÃO inverte: o claro continua mais claro que o escuro', () {
      final claro = SJBasemap.aplicar(m, branco);
      final escuro = SJBasemap.aplicar(m, preto);
      expect(claro.computeLuminance(), greaterThan(escuro.computeLuminance()),
          reason: 'uma rampa invertida vira um mapa em negativo');
    });

    test('a saída é sempre quente — vermelho acima de azul', () {
      for (final entrada in [branco, preto, const Color(0xFF808080)]) {
        final c = SJBasemap.aplicar(m, entrada);
        expect(c.r, greaterThan(c.b),
            reason: 'papel envelhecido não tem dominante fria');
      }
    });
  });

  group('atlas noturno (modo escuro)', () {
    final m = SJBasemap.matrizEscura;

    test('o branco da telha vira meia-noite', () {
      expect(SJBasemap.aplicar(m, branco), _pertoDe(const Color(0xFF0C1322)));
    });

    test('o traço vira tinta pálida', () {
      expect(SJBasemap.aplicar(m, preto), _pertoDe(const Color(0xFFAEB9CE)));
    });

    test('inverte de propósito: o branco fica MAIS escuro que o preto', () {
      final doBranco = SJBasemap.aplicar(m, branco);
      final doPreto = SJBasemap.aplicar(m, preto);
      expect(doBranco.computeLuminance(), lessThan(doPreto.computeLuminance()),
          reason: 'é o negativo que transforma papel em céu noturno');
    });
  });

  group('a rampa em si', () {
    test('cinza médio cai entre os extremos', () {
      final m = SJBasemap.matrizClara;
      final meio = SJBasemap.aplicar(m, const Color(0xFF808080));
      final claro = SJBasemap.aplicar(m, branco).computeLuminance();
      final escuro = SJBasemap.aplicar(m, preto).computeLuminance();
      expect(meio.computeLuminance(), greaterThan(escuro));
      expect(meio.computeLuminance(), lessThan(claro));
    });

    test('preserva a ordem de luminância da telha original', () {
      // Água (#AAD3DF) e terra (#F2EFE9) do estilo padrão do OSM: a terra é
      // mais clara. Se a rampa embaralhasse essa ordem, mar e continente
      // trocariam de lugar aos olhos.
      final m = SJBasemap.matrizClara;
      final agua = SJBasemap.aplicar(m, const Color(0xFFAAD3DF));
      final terra = SJBasemap.aplicar(m, const Color(0xFFF2EFE9));
      expect(terra.computeLuminance(), greaterThan(agua.computeLuminance()),
          reason: 'a terra tem de continuar mais clara que o mar');
    });

    test('a transparência passa intacta', () {
      final m = SJBasemap.matrizClara;
      expect(m[15], 0);
      expect(m[16], 0);
      expect(m[17], 0);
      expect(m[18], 1, reason: 'alfa preservado');
      expect(m[19], 0);
    });
  });
}
