import 'dart:convert';
import 'package:http/http.dart' as http;

class CategoriaResult {
  final String categoria;
  final String subcategoria;
  final String emoji;
  final double confianza;

  CategoriaResult({
    required this.categoria,
    required this.subcategoria,
    required this.emoji,
    required this.confianza,
  });
}

class GeminiService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  final String apiKey;

  GeminiService({required this.apiKey});

  /// Formatea una deuda para prompts: muestra la cuota vencida con su monto,
  /// no el saldo total acumulado, para evitar que la IA lo confunda.
  static String formatDeudaLinea(Map<String, dynamic> d) {
    final dir = d['tipo'] == 'gasto' ? 'Debo' : 'Me deben';
    final modalidad = d['modalidad'] == 'cuenta_corriente' ? 'cta.cte.' : 'fija';
    final saldo = (d['saldoPendiente'] as num).toInt();
    final cuotasPend = d['cuotasPendientes'] as int?;
    final nCuotas = d['nCuotas'] as int?;
    final proxima = d['proximaCuota'] as Map<String, dynamic>?;

    String vencidaInfo = '';
    if (d['vencida'] == true) {
      if (proxima != null) {
        final montoCuota = (proxima['monto'] as num).toInt();
        final fechaProx = DateTime.parse(proxima['fechaVencimiento'] as String);
        vencidaInfo = ' ⚠️CUOTA VENCIDA \$$montoCuota (venció ${fechaProx.day}/${fechaProx.month})';
      } else {
        vencidaInfo = ' ⚠️VENCIDA';
      }
    } else if (proxima != null) {
      final montoCuota = (proxima['monto'] as num).toInt();
      final fechaProx = DateTime.parse(proxima['fechaVencimiento'] as String);
      // Verificar si esta próxima cuota cae en un mes libre por adelanto
      final mesProxKey = '${fechaProx.year}-${fechaProx.month.toString().padLeft(2, '0')}';
      final mesesLibres = (d['mesesLibresPorAdelanto'] as List?)?.cast<String>() ?? [];
      if (mesesLibres.contains(mesProxKey)) {
        vencidaInfo = ' | próx. cuota \$$montoCuota vence ${fechaProx.day}/${fechaProx.month} ✅ YA PAGADA ANTICIPADAMENTE — NO cobrar este mes';
      } else {
        vencidaInfo = ' | próx. cuota \$$montoCuota vence ${fechaProx.day}/${fechaProx.month}';
      }
    }

    final cuotaInfo = (nCuotas != null && cuotasPend != null) ? ' ($cuotasPend/$nCuotas cuotas pend.)' : '';

    // Cuotas adelantadas: meses donde no habrá cobro por pagos anticipados
    final mesesLibres = (d['mesesLibresPorAdelanto'] as List?)?.cast<String>() ?? [];
    final cuotasAdelantadas = (d['cuotasAdelantadas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    String adelantadoInfo = '';
    if (mesesLibres.isNotEmpty) {
      final ahorroLibre = cuotasAdelantadas.fold(0, (s, c) => s + ((c['monto'] as num?)?.toInt() ?? 0));
      adelantadoInfo = ' ⚡ ${cuotasAdelantadas.length} cuota${cuotasAdelantadas.length > 1 ? "s" : ""} adelantada${cuotasAdelantadas.length > 1 ? "s" : ""} — meses libres: ${mesesLibres.join(", ")} (ahorro libre ese mes: \$$ahorroLibre)';
    }

    return '$dir "${d['descripcion']}" ($modalidad) saldo:\$$saldo$cuotaInfo$vencidaInfo$adelantadoInfo';
  }

  static String _formatSuscripciones(List<Map<String, dynamic>> suscripciones) {
    if (suscripciones.isEmpty) return '';
    final totalEsteMes = suscripciones.fold(
      0.0,
      (s, i) => s + ((i['monto_este_mes'] as num?)?.toDouble() ?? 0),
    );
    final detalle = suscripciones.map((s) {
      final estado = s['pagada_este_mes'] == true ? '[PAGADA]' : '[PENDIENTE]';
      return '  - ${s['descripcion']}: \$${(s['monto_pacto'] as num?)?.toStringAsFixed(0) ?? 0} ${s['frecuencia']} — $estado';
    }).join('\n');
    return '\nSUSCRIPCIONES Y PAGOS RECURRENTES (A considerar en flujo futuro):\n'
        '- Total exacto recurrente este mes: \$${totalEsteMes.toStringAsFixed(0)}\n'
        '$detalle\n'
        'IMPORTANTE: Evalúa si los pagos PENDIENTES afectarán la liquidez para cubrir deudas o lograr metas.\n';
  }

  static String _formatMetas(List<Map<String, dynamic>> metas) {
    if (metas.isEmpty) return 'Sin metas definidas';
    final lineas = metas.map((m) {
      final nombre = m['nombre'] ?? '';
      final emoji = m['emoji'] != null ? '${m['emoji']} ' : '';
      final actual = (m['montoActual'] as num?)?.toInt() ?? 0;
      final objetivo = (m['montoObjetivo'] as num?)?.toInt() ?? 0;
      final pct = m['progreso_pct'] ?? '0.0';
      final faltante = (m['faltante'] as num?)?.toInt() ?? (objetivo - actual);
      final mesesRest = m['mesesRestantes'] as int?;
      final ahorrNec = (m['ahorroMensualNecesario'] as num?)?.toInt();
      final completada = m['completada'] == true;
      if (completada) return '$emoji$nombre: ✅ COMPLETADA (\$$actual/\$$objetivo)';
      final ritmo = (mesesRest != null && mesesRest > 0 && ahorrNec != null)
          ? ' | necesita \$$ahorrNec/mes por $mesesRest meses'
          : '';
      return '$emoji$nombre: \$$actual/\$$objetivo ($pct%) — falta \$$faltante$ritmo';
    }).join('\n');
    return '$lineas\n'
        '(IMPORTANTE: en el historial de transacciones, los aportes a cada meta aparecen como gastos con categoria="Ahorro" y subcategoria=nombre de la meta. '
        'El campo "montoActual" ya refleja el total acumulado en cada meta. NO digas que no hay metas definidas si la lista anterior tiene entradas.)';
  }

  static String _formatIngresosEsperados(List<Map<String, dynamic>> ingresosEsperados) {
    if (ingresosEsperados.isEmpty) return '';
    // Separar recibidos vs pendientes para no inflar el total
    final recibidos = ingresosEsperados
        .where((i) => i['recibido'] == true)
        .fold(0.0, (s, i) => s + ((i['monto_este_mes'] as num?)?.toDouble() ?? 0));
    final pendientes = ingresosEsperados
        .where((i) => i['recibido'] != true)
        .fold(0.0, (s, i) => s + ((i['monto_este_mes'] as num?)?.toDouble() ?? 0));
    // Solo sumar al mes siguiente los que efectivamente tienen monto > 0 ese mes
    final totalMesViene = ingresosEsperados.fold(
      0.0,
      (s, i) => s + ((i['monto_mes_que_viene'] as num?)?.toDouble() ?? 0),
    );
    // Detalle solo de los que tienen monto en este mes (evita ruido de $0 o $1 por redondeo)
    final conMontoEsteMes = ingresosEsperados
        .where((i) => ((i['monto_este_mes'] as num?)?.toDouble() ?? 0) >= 1)
        .toList();
    final detalle = conMontoEsteMes.map((i) {
      final rec = i['esRecurrente'] == true ? ' (recurrente)' : ' (pago único)';
      final recibido = i['recibido'] == true ? ' [YA REGISTRADO EN INGRESOS]' : ' [AÚN NO RECIBIDO]';
      return '  - ${i['descripcion']}: \$${(i['monto_este_mes'] as num?) ?? 0} ${i['frecuencia']}$rec$recibido';
    }).join('\n');
    // Detalle próximo mes solo si tiene monto significativo
    final conMontoMesViene = ingresosEsperados
        .where((i) => ((i['monto_mes_que_viene'] as num?)?.toDouble() ?? 0) >= 1)
        .map((i) => '  - ${i['descripcion']}: \$${(i['monto_mes_que_viene'] as num?) ?? 0} ${i['frecuencia']}')
        .join('\n');
    final resumenMesViene = totalMesViene >= 1
        ? '- Total próximo mes: \$${totalMesViene.toStringAsFixed(0)}\n$conMontoMesViene\n'
        : '- Total próximo mes: \$0 (ningún ingreso esperado cae el mes siguiente)\n';
    return '\nINGRESOS ESPERADOS ESTE MES:\n'
        '- Ya registrados en historial: \$${recibidos.toStringAsFixed(0)} (NO sumar al total de ingresos, ya están incluidos)\n'
        '- Pendientes de recibir: \$${pendientes.toStringAsFixed(0)} (aún NO están en el historial)\n'
        '- Total esperado este mes (registrado + pendiente): \$${(recibidos + pendientes).toStringAsFixed(0)}\n'
        '$resumenMesViene'
        '${detalle.isNotEmpty ? "$detalle\n" : ""}'
        'IMPORTANTE: Si "Total próximo mes" es \$0, el usuario NO tiene ingresos registrados para el mes siguiente — NO inventes ni estimes ingresos futuros.\n';
  }

  static String _gastosPorCatPorMes(List<Map<String, dynamic>> transacciones) {
    final gastos = transacciones.where((t) => t['tipo'] == 'gasto').toList();
    if (gastos.isEmpty) return 'Sin gastos';

    // Agrupar por mes y categoría
    final porMesCat = <String, Map<String, double>>{};
    for (final t in gastos) {
      final fecha = t['fecha'].toString().substring(0, 7); // "2026-04"
      final cat = t['categoria'] as String? ?? 'Otros';
      final monto = (t['monto'] as num).toDouble();
      porMesCat.putIfAbsent(fecha, () => {});
      porMesCat[fecha]![cat] = (porMesCat[fecha]![cat] ?? 0) + monto;
    }

    final meses = porMesCat.keys.toList()..sort();
    final lines = <String>[];
    for (final mes in meses) {
      final cats = porMesCat[mes]!.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      lines.add('  $mes: ${cats.map((e) => '${e.key} \$${e.value.toStringAsFixed(0)}').join(', ')}');
    }
    return lines.join('\n');
  }

  Future<String> _llamarGemini(String prompt, {int maxTokens = 4096}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': maxTokens,
        },
      }),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] ?? response.body;
      throw Exception('Error ${response.statusCode}: $msg');
    }

    final data = jsonDecode(response.body);
    final parts = data['candidates'][0]['content']['parts'] as List;
    // Gemini 2.5 Flash (thinking model) returns multiple parts:
    // parts with "thought": true are internal reasoning, skip them
    // The actual response is the last part without "thought" flag
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i]['thought'] != true && parts[i]['text'] != null) {
        return parts[i]['text'] as String;
      }
    }
    // Fallback: return last part's text
    return parts.last['text'] as String;
  }

  Future<Map<String, dynamic>> _llamarGeminiJson(String prompt) async {
    // Gemini 2.5 Flash (thinking model): los tokens de pensamiento consumen
    // el presupuesto. Usar thinkingConfig con budgetTokens bajo para dejar
    // espacio suficiente a la respuesta JSON.
    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 8192,
          'thinkingConfig': {
            'thinkingBudget': 512,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] ?? response.body;
      throw Exception('Error ${response.statusCode}: $msg');
    }

    final data = jsonDecode(response.body);
    final parts = data['candidates'][0]['content']['parts'] as List;
    // Saltar partes de pensamiento (thought: true), tomar el último texto real
    String texto = '';
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i]['thought'] != true && parts[i]['text'] != null) {
        texto = parts[i]['text'] as String;
        break;
      }
    }
    if (texto.isEmpty) texto = parts.last['text'] as String;

    final inicio = texto.indexOf('{');
    final fin = texto.lastIndexOf('}');
    if (inicio == -1 || fin == -1 || fin <= inicio) {
      throw Exception('No se encontró JSON válido en la respuesta de IA.');
    }
    try {
      return jsonDecode(texto.substring(inicio, fin + 1));
    } on FormatException catch (e) {
      throw Exception('Error al procesar respuesta de IA: ${e.message}');
    }
  }

  Future<CategoriaResult> categorizarGasto(
      String descripcion, double monto) async {
    final prompt = '''
Eres un asistente de finanzas personales. Categoriza este gasto y responde SOLO con JSON válido, sin texto adicional.

Gasto: "$descripcion" por \$${monto.toInt()}

Responde exactamente así:
{
  "categoria": "nombre de categoría principal",
  "subcategoria": "subcategoría específica",
  "emoji": "un emoji representativo",
  "confianza": 0.95
}

Categorías posibles: Comida, Transporte, Entretenimiento, Salud, Ropa, Hogar, Educación, Tecnología, Servicios, Deporte, Viajes, Otros.
''';

    final json = await _llamarGeminiJson(prompt);
    return CategoriaResult(
      categoria: json['categoria'] ?? 'Otros',
      subcategoria: json['subcategoria'] ?? '',
      emoji: json['emoji'] ?? '💸',
      confianza: (json['confianza'] as num?)?.toDouble() ?? 0.8,
    );
  }

  Future<String> consultarCoach({
    required String pregunta,
    required List<Map<String, dynamic>> contextoFinanciero,
    List<Map<String, String>> historialChat = const [],
    List<Map<String, dynamic>> ingresosEsperados = const [],
    List<Map<String, dynamic>> suscripciones = const [],
    List<Map<String, dynamic>> deudas = const [],
    List<Map<String, dynamic>> metas = const [],
  }) async {
    final resumen = contextoFinanciero
        .take(40)
        .map((t) {
          final cl = t['clasificacion'] != null ? ' [${t['clasificacion']}]' : '';
          return '${t['tipo'][0].toUpperCase()}|${t['descripcion']} \$${t['monto']}|${t['categoria']}$cl|${t['fecha'].toString().substring(0, 10)}';
        })
        .join('\n');

    // Resumen de clasificaciones — ahorro de metas va separado
    final gastos = contextoFinanciero.where((t) => t['tipo'] == 'gasto').toList();
    final coachAhorroMetas = gastos
        .where((t) => t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosOp = gastos.where((t) => t['categoria'] != 'Ahorro').toList();
    final totalInversiones = gastosOp
        .where((t) => t['clasificacion'] == 'inversion')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalNecesarios = gastosOp
        .where((t) => t['clasificacion'] == 'necesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalInnecesarios = gastosOp
        .where((t) => t['clasificacion'] == 'innecesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());

    final clasificacionResumen = (gastos.any((t) => t['clasificacion'] != null) || coachAhorroMetas > 0)
        ? '\nCLASIFICACIÓN DE GASTOS:\n'
          '  🎯 Ahorro comprometido a metas (NO es dinero libre): \$${coachAhorroMetas.toStringAsFixed(0)}\n'
          '  📈 Inversiones operativas: \$${totalInversiones.toStringAsFixed(0)}\n'
          '  ✅ Necesarios: \$${totalNecesarios.toStringAsFixed(0)}\n'
          '  🛑 Innecesarios: \$${totalInnecesarios.toStringAsFixed(0)}\n'
        : '';

    final ingresosEspStr = _formatIngresosEsperados(ingresosEsperados);
    final suscripcionesStr = _formatSuscripciones(suscripciones);

    // Resumen por categoría para desglose preciso
    final gastosPorCat = <String, double>{};
    for (final t in contextoFinanciero.where((t) => t['tipo'] == 'gasto')) {
      final cat = t['categoria'] as String? ?? 'Otros';
      gastosPorCat[cat] = (gastosPorCat[cat] ?? 0) + (t['monto'] as num).toDouble();
    }
    final catResumenCoach = (gastosPorCat.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '  ${e.key}: \$${e.value.toStringAsFixed(0)}')
        .join('\n');

    // Deudas activas para el contexto del coach
    final deudasPendCoach = deudas.where((d) => d['completada'] != true).toList();
    final deudasCoachStr = deudasPendCoach.isNotEmpty
        ? '\nDEUDAS ACTIVAS:\n${deudasPendCoach.map(formatDeudaLinea).join('\n')}\n'
        : '';

    // Construir el prompt del sistema
    final metasCoachStr = metas.isNotEmpty
        ? '\nMETAS DE AHORRO:\n${_formatMetas(metas)}\n'
        : '';

    final systemPrompt = '''
Eres un coach financiero personal. Tienes acceso al historial financiero del usuario.$ingresosEspStr$suscripcionesStr$deudasCoachStr$metasCoachStr
MODELO DE LA APP:
- DEUDAS FIJAS: monto pactado que se va abonando. Los pagos generan gastos reales en el historial.
- CUENTAS CORRIENTES: carpetas que acumulan items. El saldo sube con cada item y baja con pagos.
- METAS DE AHORRO: abonar genera un gasto con categoria="Ahorro" y subcategoria=nombre de la meta. El "montoActual" de cada meta ya refleja el total acumulado. Si hay metas en METAS DE AHORRO, el usuario SÍ las tiene definidas.
- CLASIFICACIÓN: necesario ✅ / innecesario 🛑 / inversión 📈
GASTOS POR CATEGORÍA (histórico completo):
$catResumenCoach$clasificacionResumen
TRANSACCIONES RECIENTES (últimas 40, formato tipo|descripción \$monto|categoría|fecha):
$resumen
INSTRUCCIÓN: Responde de forma directa y concisa. Ajusta la extensión a la complejidad de la pregunta — preguntas simples merecen respuestas cortas, análisis complejos pueden ser más detallados. Sin saludos ni presentaciones. Conecta ingresos futuros con responsabilidades actuales cuando sea relevante. Si el usuario pregunta sobre deudas o cuentas corrientes, usa el contexto que viene en la pregunta.
Si alguna deuda muestra "⚡ cuotas adelantadas" y "meses libres": señala que el usuario ya pagó esa cuota anticipadamente, que en ese mes indicado NO deberá pagar ese compromiso, y cuánto dinero extra tendrá disponible ese mes como resultado.
Si el contexto personal menciona inversiones o trabajo freelance, tómalo en cuenta.
Si la pregunta empieza con "🎮 SIMULACIÓN:", responde con el impacto cuantitativo real usando los datos del historial. Calcula fechas, montos y plazos concretos. No uses frases genéricas — usa los números reales del historial. Considera todas las deudas existentes al evaluar capacidad de pago.
''';

    // Si no hay historial, enviar como prompt simple
    if (historialChat.isEmpty) {
      final prompt = '$systemPrompt\nPREGUNTA: $pregunta';
      return await _llamarGemini(prompt);
    }

    // Con historial: construir conversación multi-turno
    final contents = <Map<String, dynamic>>[];

    // Primer turno: contexto del sistema como primer mensaje del usuario
    contents.add({
      'role': 'user',
      'parts': [{'text': systemPrompt}]
    });
    contents.add({
      'role': 'model',
      'parts': [{'text': '¡Entendido! Estoy listo para ayudarte con tu situación financiera. ¿En qué te puedo ayudar?'}]
    });

    // Historial previo de la conversación
    for (final msg in historialChat) {
      contents.add({
        'role': msg['role'],
        'parts': [{'text': msg['text']}],
      });
    }

    // Mensaje actual
    contents.add({
      'role': 'user',
      'parts': [{'text': pregunta}]
    });

    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': contents,
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 4096,
        },
      }),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] ?? response.body;
      throw Exception('Error ${response.statusCode}: $msg');
    }

    final data = jsonDecode(response.body);
    final parts = data['candidates'][0]['content']['parts'] as List;
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i]['thought'] != true && parts[i]['text'] != null) {
        return parts[i]['text'] as String;
      }
    }
    return parts.last['text'] as String;
  }

  Future<String> predecirProximoMes(
    List<Map<String, dynamic>> historial, {
    bool esMesSiguiente = false,
    List<Map<String, dynamic>> ingresosEsperados = const [],
    List<Map<String, dynamic>> suscripciones = const [],
    List<Map<String, dynamic>> deudas = const [],
    List<Map<String, dynamic>> presupuestos = const [],
  }) async {
    final ahora = DateTime.now();

    // Separar transacciones del mes actual vs historial previo
    final delMesActual = historial.where((t) {
      final fecha = DateTime.parse(t['fecha'] as String);
      return fecha.year == ahora.year && fecha.month == ahora.month;
    }).toList();

    // Pre-calcular totales para contexto preciso (histórico completo)
    final totalIngresos = historial
        .where((t) => t['tipo'] == 'ingreso')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalGastos = historial
        .where((t) => t['tipo'] == 'gasto')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalAhorro = historial
        .where((t) => t['tipo'] == 'gasto' && t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosOperativos = totalGastos - totalAhorro;
    final balanceLibre = totalIngresos - totalGastos;

    // Reales del mes actual
    final ingRealesMes = delMesActual
        .where((t) => t['tipo'] == 'ingreso')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosRealesMes = delMesActual
        .where((t) => t['tipo'] == 'gasto' && t['categoria'] != 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());

    // Días transcurridos y restantes del mes actual
    final diasEnMes = DateTime(ahora.year, ahora.month + 1, 0).day;
    final diasTranscurridos = ahora.day;
    final diasRestantes = diasEnMes - diasTranscurridos;

    // Contexto de mes actual para el prompt
    final contextoMesActual = !esMesSiguiente && delMesActual.isNotEmpty
        ? '''
SITUACIÓN REAL DEL MES ACTUAL (día $diasTranscurridos de $diasEnMes):
- Ingresos ya registrados: \$${ingRealesMes.toStringAsFixed(0)}
- Gastos ya registrados (sin ahorro): \$${gastosRealesMes.toStringAsFixed(0)}
- Días restantes del mes: $diasRestantes
'''
        : '';

    // Gastos por mes para que la IA vea la evolución real
    final gastosPorMesStr = _gastosPorCatPorMes(historial);

    // Deudas pendientes con detalle de cuotas por mes
    final deudasPend = deudas.where((d) => d['completada'] != true).toList();
    String deudasStr;
    if (deudasPend.isEmpty) {
      deudasStr = 'Sin deudas pendientes';
    } else {
      deudasStr = deudasPend.map(formatDeudaLinea).join('\n');
    }

    final ingresosEspStr = _formatIngresosEsperados(ingresosEsperados);

    final objetivoMes = esMesSiguiente ? 'el MES QUE VIENE' : 'lo que queda del MES ACTUAL';
    final instruccionMes = esMesSiguiente
        ? 'Una frase de balance general esperado para el MES QUE VIENE, correlacionando gastos reales por mes, ingresos esperados, deudas pendientes y suscripciones.'
        : 'Una frase que combine lo ya registrado en el mes actual con lo que falta por llegar (ingresos esperados aún no recibidos) y los gastos que probablemente vendrán en los $diasRestantes días restantes según el patrón histórico.';

    final prompt = '''
Eres NEXUS AI, un experto en análisis financiero holístico. Analiza el historial de transacciones del usuario y genera una PROYECCIÓN para $objetivoMes.
Responde de forma concisa y premium (máximo 100 palabras).

DEFINICIONES IMPORTANTES (no confundir):
- "Ahorro" (categoría): dinero apartado intencionalmente para metas específicas (viaje, fondo emergencia, etc.). ES un compromiso, NO dinero libre.
- "Balance libre": ingresos menos TODOS los gastos (incluido ahorro). Esto es lo que realmente sobra.
- Los presupuestos son MENSUALES. Compara solo gasto del mes vs límite.
$contextoMesActual$ingresosEspStr${_formatSuscripciones(suscripciones)}
DEUDAS Y COMPROMISOS PENDIENTES:
$deudasStr

PRESUPUESTOS MENSUALES:
${presupuestos.isEmpty ? 'Sin presupuestos' : presupuestos.map((p) => '${p['categoria']}: límite \$${p['limite']} /mes').join('\n')}

RESUMEN CALCULADO (histórico acumulado):
- Ingresos totales: \$${totalIngresos.toStringAsFixed(0)}
- Gastos operativos (sin ahorro): \$${gastosOperativos.toStringAsFixed(0)}
- Ahorro comprometido a metas: \$${totalAhorro.toStringAsFixed(0)}
- Balance libre real: \$${balanceLibre.toStringAsFixed(0)}

GASTOS POR MES Y CATEGORÍA (para ver evolución real):
$gastosPorMesStr

Estructura de la respuesta:
- $instruccionMes
- Un consejo estratégico considerando SOLO las cuotas/compromisos que vencen en $objetivoMes (NO menciones cuotas ya pagadas ni de meses futuros). Menciona el impacto real en el dinero libre. Si hay suscripciones que se cobran, inclúyelas.
- Usa emojis de forma profesional.
IMPORTANTE: Solo menciona deudas y cuotas que aparezcan con fecha en $objetivoMes. No inventes vencimientos ni repitas pagos ya realizados.
''';

    return await _llamarGemini(prompt);
  }

  /// Calcula el score financiero del usuario (0-100) con análisis detallado
  Future<Map<String, dynamic>> calcularScoreFinanciero({
    required List<Map<String, dynamic>> transacciones,
    required List<Map<String, dynamic>> transaccionesMesActual,
    required List<Map<String, dynamic>> metas,
    required List<Map<String, dynamic>> presupuestos,
    required List<Map<String, dynamic>> deudas,
    List<Map<String, dynamic>> ingresosEsperados = const [],
    List<Map<String, dynamic>> suscripciones = const [],
  }) async {
    // Totales históricos
    final totalIngresos = transacciones
        .where((t) => t['tipo'] == 'ingreso')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalGastos = transacciones
        .where((t) => t['tipo'] == 'gasto')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    // Totales del mes actual (mismo período que estadísticas muestra por defecto)
    final mesIngresos = transaccionesMesActual
        .where((t) => t['tipo'] == 'ingreso')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final mesGastos = transaccionesMesActual
        .where((t) => t['tipo'] == 'gasto')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final mesAhorro = transaccionesMesActual
        .where((t) => t['tipo'] == 'gasto' && t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final ratioAhorroMesActual = mesIngresos > 0
        ? (mesAhorro / mesIngresos * 100).toStringAsFixed(1)
        : '0.0';

    // Ratio de ahorro promedio histórico (todos los meses desde ene 2026)
    final totalAhorroHistorico = transacciones
        .where((t) => t['tipo'] == 'gasto' && t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final ratioAhorroHistorico = totalIngresos > 0
        ? (totalAhorroHistorico / totalIngresos * 100).toStringAsFixed(1)
        : '0.0';

    // Gastos por categoría
    final porCategoria = <String, double>{};
    for (final t in transacciones.where((t) => t['tipo'] == 'gasto')) {
      final cat = t['categoria'] as String? ?? 'Otros';
      porCategoria[cat] = (porCategoria[cat] ?? 0) + (t['monto'] as num).toDouble();
    }
    final catResumen = (porCategoria.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(8)
        .map((e) => '  ${e.key}: \$${e.value.toStringAsFixed(0)}')
        .join('\n');

    // Clasificación de gastos — ahorro de metas va separado
    final gastos = transacciones.where((t) => t['tipo'] == 'gasto').toList();
    final totalAhorroMetas = gastos
        .where((t) => t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosOperativos = gastos.where((t) => t['categoria'] != 'Ahorro').toList();
    final totalInversiones = gastosOperativos
        .where((t) => t['clasificacion'] == 'inversion')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalNecesarios = gastosOperativos
        .where((t) => t['clasificacion'] == 'necesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalInnecesarios = gastosOperativos
        .where((t) => t['clasificacion'] == 'innecesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosSinClasificar = gastosOperativos
        .where((t) => t['clasificacion'] == null)
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final hayClasificacion = (totalInversiones + totalNecesarios + totalInnecesarios) > 0;

    // ratio de ahorro real = lo apartado a metas / ingresos (no balance libre)
    final ratioAhorroMetas = totalIngresos > 0
        ? ((totalAhorroMetas / totalIngresos) * 100).toStringAsFixed(1)
        : '0.0';
    final balanceLibre = totalIngresos - totalGastos;

    final clasificacionResumen = hayClasificacion
        ? '\n- Ahorro comprometido a metas: \$${totalAhorroMetas.toStringAsFixed(0)} ($ratioAhorroMetas% de ingresos)'
          '\n- Inversiones operativas (retorno esperado): \$${totalInversiones.toStringAsFixed(0)}'
          '\n- Gastos necesarios: \$${totalNecesarios.toStringAsFixed(0)}'
          '\n- Gastos innecesarios: \$${totalInnecesarios.toStringAsFixed(0)}'
          '\n- Sin clasificar: \$${gastosSinClasificar.toStringAsFixed(0)}'
        : '\n- Ahorro comprometido a metas: \$${totalAhorroMetas.toStringAsFixed(0)}'
          '\n- (Resto de gastos sin clasificar)';

    final metasResumen = _formatMetas(metas);

    final presupuestosResumen = presupuestos
        .map((p) => '${p['categoria']}: límite \$${p['limite']}')
        .join('\n');

    // Resumen de deudas
    final deudasPendientes = deudas.where((d) => d['completada'] != true).toList();
    final totalDebo = deudasPendientes
        .where((d) => d['tipo'] == 'gasto')
        .fold(0.0, (s, d) => s + (d['saldoPendiente'] as num).toDouble());
    final totalMeDeben = deudasPendientes
        .where((d) => d['tipo'] == 'ingreso')
        .fold(0.0, (s, d) => s + (d['saldoPendiente'] as num).toDouble());
    final hayVencidas = deudasPendientes.any((d) => d['vencida'] == true);
    final deudasResumen = deudasPendientes.isEmpty
        ? 'Sin deudas pendientes'
        : deudasPendientes.map(formatDeudaLinea).join('\n');

    final prompt = '''
Eres NEXUS AI, analista financiero. Genera un SCORE FINANCIERO basado en los datos pre-calculados que siguen. NO calcules ni estimes nada por tu cuenta — solo interpreta y puntúa.
MODELO DE LA APP:
- "Ahorro" (categoría): dinero comprometido a metas específicas, no dinero libre. Es un hábito positivo. Las tx de ahorro tienen subcategoria=nombre de la meta.
- "Balance libre": ingresos − todos los gastos (incluido ahorro). Dinero realmente disponible.
- deuda_fija: monto pactado que se abona. cuenta_corriente: saldo sube con items y baja con pagos.
- Si METAS DE AHORRO tiene entradas, el usuario SÍ tiene metas. El montoActual ya refleja lo acumulado. NUNCA digas que no tiene metas definidas.

HISTÓRICO COMPLETO:
- Ingresos: \$${totalIngresos.toStringAsFixed(0)} | Gastos (incl. ahorro): \$${totalGastos.toStringAsFixed(0)} | Balance libre: \$${balanceLibre.toStringAsFixed(0)}
- Ahorro histórico a metas: \$${totalAhorroHistorico.toStringAsFixed(0)} ($ratioAhorroHistorico% de ingresos) ← usar para dimensión "ahorro"
- Transacciones registradas: ${transacciones.length}

MES ACTUAL:
- Ingresos: \$${mesIngresos.toStringAsFixed(0)} | Gastos op.: \$${(mesGastos - mesAhorro).toStringAsFixed(0)} | Ahorro: \$${mesAhorro.toStringAsFixed(0)} ($ratioAhorroMesActual%) | Balance: \$${(mesIngresos - mesGastos).toStringAsFixed(0)}

CLASIFICACIÓN DE GASTOS HISTÓRICA:$clasificacionResumen

TOP CATEGORÍAS DE GASTO:
${catResumen.isEmpty ? 'Sin gastos' : catResumen}

METAS DE AHORRO:
$metasResumen
PRESUPUESTOS: ${presupuestosResumen.isEmpty ? 'Sin presupuestos' : presupuestosResumen}

DEUDAS:
- Debo: \$${totalDebo.toStringAsFixed(0)} | Me deben: \$${totalMeDeben.toStringAsFixed(0)}${hayVencidas ? ' | ⚠️ HAY VENCIDAS' : ''}
$deudasResumen
${_formatIngresosEsperados(ingresosEsperados)}${_formatSuscripciones(suscripciones)}
Responde SOLO con JSON válido:
{
  "score": 75,
  "nivel": "Bueno",
  "color": "verde",
  "resumen": "1 oración sobre estado financiero general.",
  "dimensiones": {
    "ahorro": {"valor": 70, "descripcion": "Históricamente ahorras $ratioAhorroHistorico% de tus ingresos"},
    "consistencia": {"valor": 85, "descripcion": "Breve descripción"},
    "control": {"valor": 65, "descripcion": "Breve descripción"},
    "metas": {"valor": 60, "descripcion": "Breve descripción"},
    "habitos": {"valor": 80, "descripcion": "Breve descripción"}
  },
  "fortalezas": ["fortaleza con datos concretos", "fortaleza 2"],
  "areas_mejora": ["área con datos concretos", "área 2"],
  "consejo_principal": "Consejo accionable concreto."
}

Reglas: score 0-100. nivel: Crítico(0-30), Regular(31-50), Bueno(51-70), Excelente(71-90), Maestro(91-100).
ahorro: ratio histórico $ratioAhorroHistorico%. <5%→bajo, 5-20%→medio, >20%→alto.
control: penalizar si deudas vencidas o gasto innecesario > ingresos esperados.
patrimonio: balance histórico \$${balanceLibre.toStringAsFixed(0)} es colchón de seguridad — no sobrepenalices un mes flojo si el acumulado es sólido.
''';

    final json = await _llamarGeminiJson(prompt);
    return json;
  }

  /// Analiza patrones de gasto e identifica anomalías y tendencias
  Future<Map<String, dynamic>> analizarPatrones(
      List<Map<String, dynamic>> transacciones, {
      List<Map<String, dynamic>> deudas = const [],
      List<Map<String, dynamic>> metas = const [],
      List<Map<String, dynamic>> presupuestos = const [],
      List<Map<String, dynamic>> ingresosEsperados = const [],
      List<Map<String, dynamic>> suscripciones = const [],
  }) async {
    // Pre-calcular estadísticas para contexto preciso
    final totalIngresos = transacciones
        .where((t) => t['tipo'] == 'ingreso')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalGastos = transacciones
        .where((t) => t['tipo'] == 'gasto')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final balance = totalIngresos - totalGastos;

    final porCategoria = <String, double>{};
    for (final t in transacciones.where((t) => t['tipo'] == 'gasto')) {
      final cat = t['categoria'] as String? ?? 'Otros';
      porCategoria[cat] = (porCategoria[cat] ?? 0) + (t['monto'] as num).toDouble();
    }
    final catResumen = (porCategoria.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '  ${e.key}: \$${e.value.toStringAsFixed(0)}')
        .join('\n');

    // Clasificación para patrones — ahorro de metas separado
    final gastosLista = transacciones.where((t) => t['tipo'] == 'gasto').toList();
    final patronAhorroMetas = gastosLista
        .where((t) => t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosOpLista = gastosLista.where((t) => t['categoria'] != 'Ahorro').toList();
    final montoInversiones = gastosOpLista
        .where((t) => t['clasificacion'] == 'inversion')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final montoNecesarios = gastosOpLista
        .where((t) => t['clasificacion'] == 'necesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final montoInnecesarios = gastosOpLista
        .where((t) => t['clasificacion'] == 'innecesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final totalGastosClasificados = montoInversiones + montoNecesarios + montoInnecesarios;
    final pctInnecesarios = totalGastosClasificados > 0
        ? (montoInnecesarios / totalGastosClasificados * 100).toStringAsFixed(1)
        : '0.0';

    final clasificacionStr = (totalGastosClasificados > 0 || patronAhorroMetas > 0)
        ? '🎯 Ahorro metas (comprometido, no libre): \$${patronAhorroMetas.toStringAsFixed(0)} | 📈 Inversiones: \$${montoInversiones.toStringAsFixed(0)} | ✅ Necesarios: \$${montoNecesarios.toStringAsFixed(0)} | 🛑 Innecesarios: \$${montoInnecesarios.toStringAsFixed(0)} ($pctInnecesarios% del total clasificado)'
        : 'Sin clasificación asignada aún';

    // Top 15 gastos más altos para detectar anomalías (formato compacto)
    final top20Gastos = (transacciones.where((t) => t['tipo'] == 'gasto').toList()
          ..sort((a, b) => (b['monto'] as num).compareTo(a['monto'] as num)))
        .take(15)
        .map((t) {
          final cl = t['clasificacion'] != null ? '[${t['clasificacion']}]' : '';
          return '\$${t['monto']}|${t['categoria']}$cl|${t['fecha'].toString().substring(0, 7)}';
        })
        .join('\n');

    // Resumen de deudas para patrones
    final deudasPend = deudas.where((d) => d['completada'] != true).toList();
    final totalDeboP = deudasPend
        .where((d) => d['tipo'] == 'gasto')
        .fold(0.0, (s, d) => s + (d['saldoPendiente'] as num).toDouble());
    final cuentasCorrientes = deudasPend.where((d) => d['modalidad'] == 'cuenta_corriente').toList();
    final deudasPatronStr = deudasPend.isEmpty
        ? 'Sin deudas pendientes'
        : deudasPend.map(formatDeudaLinea).join('\n');

    final prompt = '''
Eres NEXUS AI, experto en comportamiento financiero. Detecta PATRONES con los datos pre-calculados. NO recalcules — solo interpreta.
CONTEXTO: Pagos a deudas = gastos normales. Metas de ahorro = gastos con categoria="Ahorro" y subcategoria=nombre de la meta (hábito positivo, no gasto libre). Si hay metas en la lista, el usuario SÍ las tiene — el montoActual refleja lo acumulado. NUNCA digas que no tiene metas.

RESUMEN FINANCIERO (exacto):
- Ingresos: \$${totalIngresos.toStringAsFixed(0)} | Gastos: \$${totalGastos.toStringAsFixed(0)} | Balance: \$${balance.toStringAsFixed(0)} | Tx: ${transacciones.length}
- Deuda pendiente (debo): \$${totalDeboP.toStringAsFixed(0)} | Cuentas corrientes activas: ${cuentasCorrientes.length}

CLASIFICACIÓN: $clasificacionStr

GASTOS POR CATEGORÍA (histórico):
${catResumen.isEmpty ? 'Sin gastos' : catResumen}

GASTOS POR MES Y CATEGORÍA (para comparar vs presupuestos — un mes vs su límite, jamás acumulado):
${_gastosPorCatPorMes(transacciones)}

METAS DE AHORRO:
${_formatMetas(metas)}
PRESUPUESTOS MENSUALES: ${presupuestos.isEmpty ? 'Sin presupuestos' : presupuestos.map((p) => '${p['categoria']} \$${p['limite']}/mes').join(' | ')}

DEUDAS: $deudasPatronStr
${_formatIngresosEsperados(ingresosEsperados)}${_formatSuscripciones(suscripciones)}
TOP 15 GASTOS (monto|categoría[clasif]|mes):
$top20Gastos

Responde SOLO con JSON válido:
{
  "patrones": [{"titulo":"...","descripcion":"...","tipo":"riesgo","impacto":"alto","emoji":"📅"}],
  "anomalias": [{"descripcion":"...","monto":0.0,"categoria":"...","emoji":"⚠️"}],
  "categoria_principal": "...",
  "dia_mayor_gasto": "...",
  "tendencia_mensual": "creciente",
  "insight_clave": "Insight predictivo holístico conectando ingresos futuros con deudas y gastos."
}

Tipos: habito|tendencia|riesgo|oportunidad. Impacto: alto|medio|bajo. Tendencia: creciente|estable|decreciente.
Patrimonio acumulado \$${balance.toStringAsFixed(0)}: colchón real. No dramatices un mes flojo si el histórico es sólido.
Máximo 4 patrones y 2 anomalías.
''';

    final json = await _llamarGeminiJson(prompt);
    return json;
  }

  /// Genera alertas inteligentes basadas en el ritmo de gasto actual
  Future<List<Map<String, dynamic>>> generarAlertasInteligentes({
    required List<Map<String, dynamic>> transaccionesDelMes,
    required List<Map<String, dynamic>> presupuestos,
    required List<Map<String, dynamic>> deudas,
    required int diasTranscurridos,
    required int diasTotalesMes,
    double balanceAcumulado = 0,
    List<Map<String, dynamic>> metas = const [],
    List<Map<String, dynamic>> ingresosEsperados = const [],
    List<Map<String, dynamic>> suscripciones = const [],
  }) async {
    final gastosDelMes = transaccionesDelMes.where((t) => t['tipo'] == 'gasto').toList();

    // Totales de clasificación del mes
    final mesInversiones = gastosDelMes
        .where((t) => t['clasificacion'] == 'inversion')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final mesNecesarios = gastosDelMes
        .where((t) => t['clasificacion'] == 'necesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final mesInnecesarios = gastosDelMes
        .where((t) => t['clasificacion'] == 'innecesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final mesAhorro = gastosDelMes
        .where((t) => t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final mesTotal = gastosDelMes.fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());

    // Gastos NETOS por categoría del mes (gastos − ingresos de la misma cat, mín 0)
    final gastosPorCatMes = <String, double>{};
    for (final t in transaccionesDelMes) {
      final cat = t['categoria'] as String? ?? 'Otros';
      if (cat.startsWith('Ahorro')) continue;
      final monto = (t['monto'] as num).toDouble();
      if (t['tipo'] == 'gasto') {
        gastosPorCatMes[cat] = (gastosPorCatMes[cat] ?? 0) + monto;
      } else if (t['tipo'] == 'ingreso') {
        gastosPorCatMes[cat] = (gastosPorCatMes[cat] ?? 0) - monto;
      }
    }
    gastosPorCatMes.removeWhere((_, v) => v <= 0);
    final gastosResumen = (gastosPorCatMes.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '${e.key}: \$${e.value.toStringAsFixed(0)}')
        .join(' | ');

    final presupuestosResumen = presupuestos
        .map((p) => '${p['categoria']}: límite \$${p['limite']}')
        .join('\n');

    // Resumen de deudas para alertas
    final deudasPendA = deudas.where((d) => d['completada'] != true).toList();
    final vencidas = deudasPendA.where((d) => d['vencida'] == true).toList();
    final corrientesAltas = deudasPendA
        .where((d) => d['modalidad'] == 'cuenta_corriente' && (d['saldoPendiente'] as num) > 0)
        .toList();
    final deudasAlertaStr = deudasPendA.isEmpty
        ? 'Sin deudas pendientes'
        : deudasPendA.map(formatDeudaLinea).join('\n');

    final prompt = '''
Eres NEXUS AI. Genera ALERTAS INTELIGENTES PROACTIVAS con los datos exactos provistos. NO calcules — solo interpreta.

DÍA: $diasTranscurridos/$diasTotalesMes (${(diasTranscurridos / diasTotalesMes * 100).toStringAsFixed(0)}% del mes transcurrido)
BALANCE HISTÓRICO ACUMULADO: \$${balanceAcumulado.toStringAsFixed(0)} (colchón de seguridad — modera urgencia si es alto)

GASTOS DEL MES POR CATEGORÍA: ${gastosResumen.isEmpty ? 'Sin gastos' : gastosResumen}
TOTAL GASTADO: \$${mesTotal.toStringAsFixed(0)} | Ahorro metas: \$${mesAhorro.toStringAsFixed(0)} | Inversiones: \$${mesInversiones.toStringAsFixed(0)} | Necesarios: \$${mesNecesarios.toStringAsFixed(0)} | Innecesarios: \$${mesInnecesarios.toStringAsFixed(0)}

PRESUPUESTOS MENSUALES: ${presupuestosResumen.isEmpty ? 'Sin presupuestos' : presupuestosResumen}

DEUDAS: $deudasAlertaStr
- Vencidas: ${vencidas.length} | Cuentas corrientes con saldo: ${corrientesAltas.length}

METAS DE AHORRO:
${_formatMetas(metas)}
${_formatIngresosEsperados(ingresosEsperados)}${_formatSuscripciones(suscripciones)}
Responde SOLO con JSON válido:
{"alertas":[{"titulo":"...","mensaje":"Máx 2 oraciones accionables.","tipo":"presupuesto","urgencia":"alta","emoji":"⚠️","categoria":"cat o null"}]}

Tipos: presupuesto|ritmo|oportunidad|meta|innecesario|deuda
Urgencia: alta(rojo)|media(amarillo)|baja(verde)
Si hay ingreso esperado próximo, reduce urgencia de ritmo. Si hay deudas vencidas + gasto innecesario alto, urgencia alta.
Máximo 5 alertas.
''';

    final json = await _llamarGeminiJson(prompt);
    final alertas = json['alertas'] as List? ?? [];
    return alertas.cast<Map<String, dynamic>>();
  }

  /// Genera insights avanzados: velocidad a metas, ratio ahorro real,
  /// concentración de riesgo, volatilidad de ingresos y flujo de caja 30 días.
  Future<Map<String, dynamic>> generarInsightsAvanzados({
    required List<Map<String, dynamic>> transacciones,
    required List<Map<String, dynamic>> metas,
    required List<Map<String, dynamic>> deudas,
    required List<Map<String, dynamic>> ingresosEsperados,
    required List<Map<String, dynamic>> suscripciones,
  }) async {
    final ahora = DateTime.now();

    // ── Ingresos por mes (últimos 6 meses) ──────────────────────────────────
    final ingresosPorMes = <String, double>{};
    for (final t in transacciones.where((t) => t['tipo'] == 'ingreso')) {
      final fecha = t['fecha'].toString().substring(0, 7);
      ingresosPorMes[fecha] = (ingresosPorMes[fecha] ?? 0) + (t['monto'] as num).toDouble();
    }
    final mesesOrdenados = ingresosPorMes.keys.toList()..sort();
    final ultimos6Meses = mesesOrdenados.length > 6
        ? mesesOrdenados.sublist(mesesOrdenados.length - 6)
        : mesesOrdenados;
    final ingMeses = ultimos6Meses.map((m) => '  $m: \$${ingresosPorMes[m]!.toStringAsFixed(0)}').join('\n');

    // Volatilidad: desv. estándar / promedio de ingresos mensuales
    final valoresIng = ultimos6Meses.map((m) => ingresosPorMes[m]!).toList();
    final promedioIng = valoresIng.isNotEmpty
        ? valoresIng.fold(0.0, (s, v) => s + v) / valoresIng.length
        : 0.0;
    final varianzaIng = valoresIng.isNotEmpty
        ? valoresIng.fold(0.0, (s, v) => s + (v - promedioIng) * (v - promedioIng)) / valoresIng.length
        : 0.0;
    // sqrt de varianza via Newton-Raphson (sin necesitar dart:math)
    double sqrtDesvIng = 0.0;
    if (varianzaIng > 0) {
      double x = varianzaIng / 2;
      for (int i = 0; i < 25; i++) { x = (x + varianzaIng / x) / 2; }
      sqrtDesvIng = x;
    }
    final cvIng = promedioIng > 0 ? (sqrtDesvIng / promedioIng * 100) : 0.0;

    // ── Gastos por categoría histórico ───────────────────────────────────────
    final gastosPorCat = <String, double>{};
    double totalGastosHistorico = 0;
    for (final t in transacciones.where((t) => t['tipo'] == 'gasto')) {
      final cat = t['categoria'] as String? ?? 'Otros';
      final monto = (t['monto'] as num).toDouble();
      gastosPorCat[cat] = (gastosPorCat[cat] ?? 0) + monto;
      totalGastosHistorico += monto;
    }
    final catConcentracion = (gastosPorCat.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) {
          final pct = totalGastosHistorico > 0
              ? (e.value / totalGastosHistorico * 100).toStringAsFixed(1)
              : '0';
          return '  ${e.key}: \$${e.value.toStringAsFixed(0)} ($pct%)';
        })
        .join('\n');

    // ── Ahorro real del mes actual ───────────────────────────────────────────
    final delMesActual = transacciones.where((t) {
      final fecha = t['fecha'].toString().substring(0, 7);
      return fecha == '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';
    }).toList();
    final ingresosMes = delMesActual
        .where((t) => t['tipo'] == 'ingreso')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosMes = delMesActual
        .where((t) => t['tipo'] == 'gasto')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final ahorroMes = ingresosMes - gastosMes;
    final ratioAhorroMes = ingresosMes > 0 ? (ahorroMes / ingresosMes * 100) : 0.0;

    // Ahorro promedio mensual histórico (todos los meses)
    double totalIngHistorico = 0;
    double totalAhorroHistoricoReal = 0;
    for (final mes in mesesOrdenados) {
      final ingMes = ingresosPorMes[mes] ?? 0;
      final gastMes = transacciones
          .where((t) => t['tipo'] == 'gasto' && t['fecha'].toString().startsWith(mes))
          .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
      totalIngHistorico += ingMes;
      totalAhorroHistoricoReal += (ingMes - gastMes);
    }
    final ratioAhorroHistorico = totalIngHistorico > 0
        ? (totalAhorroHistoricoReal / totalIngHistorico * 100)
        : 0.0;

    // ── Velocidad a metas ────────────────────────────────────────────────────
    // Ahorro promedio mensual en categoría "Ahorro" de los últimos 3 meses
    double totalAhorroCat3m = 0;
    for (int i = 1; i <= 3; i++) {
      final fecha = DateTime(ahora.year, ahora.month - i, 1);
      final clave = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';
      totalAhorroCat3m += transacciones
          .where((t) =>
              t['tipo'] == 'gasto' &&
              (t['categoria'] as String).startsWith('Ahorro') &&
              t['fecha'].toString().startsWith(clave))
          .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    }
    final ahorroMensualPromedio = totalAhorroCat3m / 3;

    final metasStr = metas.map((m) {
      final faltante = ((m['montoObjetivo'] as num) - (m['montoActual'] as num)).toDouble();
      final mesesRestantes = ahorroMensualPromedio > 0
          ? (faltante / ahorroMensualPromedio).ceil()
          : -1;
      final fechaLimite = m['fechaLimite'] != null
          ? m['fechaLimite'].toString().substring(0, 10)
          : 'sin límite';
      return '  ${m['nombre']}: \$${(m['montoActual'] as num).toInt()}/\$${(m['montoObjetivo'] as num).toInt()}'
          ' | faltante: \$${faltante.toInt()}'
          ' | a este ritmo: ${mesesRestantes >= 0 ? "$mesesRestantes meses" : "sin aportes"}'
          ' | fecha límite: $fechaLimite';
    }).join('\n');

    // ── Flujo de caja próximos 30 días ───────────────────────────────────────
    final eventos30Dias = <Map<String, dynamic>>[];
    // Cuotas de deuda (solo si no están ya pagadas)
    for (final d in deudas.where((d) => d['completada'] != true)) {
      final prox = d['proximaCuota'] as Map<String, dynamic>?;
      if (prox != null) {
        final numeroCuota = prox['numero'];
        // Verificar que esta cuota no esté en cuotasPagadasEsteMes
        final pagadasEsteMes = (d['cuotasPagadasEsteMes'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];
        final yaEstaPagada = pagadasEsteMes.any(
          (c) => c['numero'] == numeroCuota,
        );
        if (yaEstaPagada) continue;

        final fecha = DateTime.parse(prox['fechaVencimiento'] as String);
        final diffDias = fecha.difference(ahora).inDays;
        if (diffDias >= 0 && diffDias <= 30) {
          eventos30Dias.add({
            'tipo': 'egreso',
            'descripcion': 'Cuota ${d['descripcion']}',
            'monto': prox['monto'],
            'dia': diffDias,
            'fecha': prox['fechaVencimiento'].toString().substring(0, 10),
          });
        }
      }
    }
    // Suscripciones pendientes
    for (final s in suscripciones.where((s) => s['pagada_este_mes'] != true)) {
      eventos30Dias.add({
        'tipo': 'egreso',
        'descripcion': 'Suscripción ${s['descripcion']}',
        'monto': s['monto_este_mes'] ?? s['monto_pacto'],
        'dia': '~próximos días',
        'fecha': 'este mes',
      });
    }
    // Ingresos esperados pendientes
    for (final i in ingresosEsperados.where((i) => i['recibido'] != true)) {
      final montoPendiente = (i['monto_este_mes'] as num?)?.toDouble() ?? 0;
      if (montoPendiente > 0) {
        eventos30Dias.add({
          'tipo': 'ingreso',
          'descripcion': 'Ingreso esperado: ${i['descripcion']}',
          'monto': montoPendiente,
          'dia': 'pendiente',
          'fecha': i['fechaEsperada'].toString().substring(0, 10),
        });
      }
    }
    final flujoStr = eventos30Dias.isEmpty
        ? 'Sin eventos futuros registrados'
        : eventos30Dias.map((e) {
            final signo = e['tipo'] == 'ingreso' ? '+' : '-';
            return '  ${e['fecha']}: $signo\$${(e['monto'] as num).toInt()} — ${e['descripcion']}';
          }).join('\n');

    // ── Ratio de emergencia ──────────────────────────────────────────────────
    final balanceLibre = totalIngHistorico - transacciones
        .where((t) => t['tipo'] == 'gasto')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final promedioGastosMensual = mesesOrdenados.isNotEmpty
        ? transacciones
                .where((t) => t['tipo'] == 'gasto')
                .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble()) /
            mesesOrdenados.length
        : 0.0;
    final mesesEmergencia = promedioGastosMensual > 0
        ? balanceLibre / promedioGastosMensual
        : 0.0;

    final prompt = '''
Eres NEXUS AI, analista financiero. Genera insights avanzados con los datos pre-calculados. NO calcules — solo interpreta y enriquece.

RATIO DE AHORRO REAL:
- Este mes: ahorro neto \$${ahorroMes.toStringAsFixed(0)} de ingresos \$${ingresosMes.toStringAsFixed(0)} = ${ratioAhorroMes.toStringAsFixed(1)}%
- Histórico promedio: ${ratioAhorroHistorico.toStringAsFixed(1)}% (ingresos - todos los gastos / ingresos)
- Estándar recomendado: 20% o más

VELOCIDAD A METAS (aportes promedio últimos 3 meses: \$${ahorroMensualPromedio.toStringAsFixed(0)}/mes):
${metasStr.isEmpty ? 'Sin metas definidas' : metasStr}

CONCENTRACIÓN DE RIESGO POR CATEGORÍA (histórico):
${catConcentracion.isEmpty ? 'Sin gastos' : catConcentracion}
Total histórico: \$${totalGastosHistorico.toStringAsFixed(0)}

VOLATILIDAD DE INGRESOS (últimos ${ultimos6Meses.length} meses):
$ingMeses
- Promedio mensual: \$${promedioIng.toStringAsFixed(0)}
- Coeficiente de variación: ${cvIng.toStringAsFixed(1)}% (< 15% = estable, 15-40% = moderado, > 40% = volátil)

FONDO DE EMERGENCIA:
- Balance libre acumulado: \$${balanceLibre.toStringAsFixed(0)}
- Gasto mensual promedio: \$${promedioGastosMensual.toStringAsFixed(0)}
- Cobertura: ${mesesEmergencia.toStringAsFixed(1)} meses (recomendado: 3-6 meses)

FLUJO DE CAJA PRÓXIMOS 30 DÍAS:
$flujoStr

Responde SOLO con JSON válido:
{
  "ratio_ahorro": {
    "porcentaje_mes": ${ratioAhorroMes.toStringAsFixed(1)},
    "porcentaje_historico": ${ratioAhorroHistorico.toStringAsFixed(1)},
    "nivel": "bajo|moderado|bueno|excelente",
    "comentario": "1 oración con contexto y comparación vs estándar 20%"
  },
  "velocidad_metas": [
    {"nombre": "...", "meses_restantes": 0, "en_plazo": true, "comentario": "1 oración"}
  ],
  "concentracion_riesgo": {
    "categoria_principal": "...",
    "porcentaje_principal": 0.0,
    "nivel_riesgo": "bajo|moderado|alto",
    "comentario": "1 oración sobre diversificación o concentración"
  },
  "volatilidad_ingresos": {
    "coeficiente": ${cvIng.toStringAsFixed(1)},
    "nivel": "estable|moderado|volatil",
    "meses_emergencia_recomendados": 3,
    "comentario": "1 oración sobre estabilidad y fondo recomendado"
  },
  "liquidez_emergencia": {
    "meses_cobertura": ${mesesEmergencia.toStringAsFixed(1)},
    "nivel": "critico|bajo|adecuado|excelente",
    "comentario": "1 oración sobre el colchón de seguridad"
  },
  "flujo_30_dias": {
    "eventos": [{"fecha": "...", "tipo": "ingreso|egreso", "descripcion": "...", "monto": 0}],
    "saldo_minimo_proyectado": 0,
    "alerta": "null o 1 oración si hay riesgo de liquidez"
  },
  "insight_global": "2 oraciones: el dato más sorprendente o importante y 1 acción concreta."
}
''';

    final json = await _llamarGeminiJson(prompt);
    return json;
  }

  /// Genera resumen financiero del período (semana, mes, año)
  Future<Map<String, dynamic>> generarResumenPeriodo({
    required List<Map<String, dynamic>> transacciones,
    required String periodo,
    required double totalIngresos,
    required double totalGastos,
    required Map<String, double> gastosPorCategoria,
    List<Map<String, dynamic>> deudas = const [],
    List<Map<String, dynamic>> metas = const [],
    List<Map<String, dynamic>> presupuestos = const [],
    List<Map<String, dynamic>> ingresosEsperados = const [],
    List<Map<String, dynamic>> suscripciones = const [],
    int diasRestantes = 0,
    double ingresosProyectados = 0,
    double gastosProyectados = 0,
    int mesesEnPeriodo = 1,
  }) async {
    // Separar ahorro de metas del resto de gastos
    final gastosLst = transacciones.where((t) => t['tipo'] == 'gasto').toList();
    final pAhorro = gastosLst
        .where((t) => t['categoria'] == 'Ahorro')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final gastosOp = gastosLst.where((t) => t['categoria'] != 'Ahorro').toList();
    final pInversiones = gastosOp
        .where((t) => t['clasificacion'] == 'inversion')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final pNecesarios = gastosOp
        .where((t) => t['clasificacion'] == 'necesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final pInnecesarios = gastosOp
        .where((t) => t['clasificacion'] == 'innecesario')
        .fold(0.0, (s, t) => s + (t['monto'] as num).toDouble());
    final hayClasif = (pInversiones + pNecesarios + pInnecesarios + pAhorro) > 0;

    final ratioAhorro = totalIngresos > 0
        ? (pAhorro / totalIngresos * 100).toStringAsFixed(1)
        : '0.0';
    final balanceLibre = totalIngresos - totalGastos;

    final catResumen = gastosPorCategoria.entries
        .map((e) => '${e.key}: \$${e.value.toStringAsFixed(0)}')
        .join('\n');

    final clasificacionPeriodo = hayClasif
        ? '\n🎯 AHORRO A METAS (comprometido, no libre): \$${pAhorro.toStringAsFixed(0)} ($ratioAhorro% de ingresos)'
          '\n📈 INVERSIONES OPERATIVAS: \$${pInversiones.toStringAsFixed(0)}'
          '\n✅ NECESARIOS: \$${pNecesarios.toStringAsFixed(0)}'
          '\n🛑 INNECESARIOS: \$${pInnecesarios.toStringAsFixed(0)}'
        : '';

    // Pre-calcular comparación presupuesto vs gasto real para evitar errores de la IA
    // Para períodos multi-mes (año, semanas) el límite se escala por los meses del período
    final presupuestosConGasto = presupuestos.map((p) {
      final cat = p['categoria'] as String;
      final limiteMensual = (p['limite'] as num).toDouble();
      final limiteEscalado = limiteMensual * mesesEnPeriodo;
      final gastado = gastosPorCategoria[cat] ?? 0.0;
      final diferencia = gastado - limiteEscalado;
      final porcentaje = limiteEscalado > 0 ? (gastado / limiteEscalado * 100).toStringAsFixed(0) : '0';
      final estado = gastado > limiteEscalado
          ? 'SUPERADO en \$${diferencia.toStringAsFixed(0)} (${porcentaje}% del límite)'
          : 'OK — quedan \$${(-diferencia).toStringAsFixed(0)} disponibles (${porcentaje}% usado)';
      final escalaStr = mesesEnPeriodo > 1 ? ' (límite mensual \$${limiteMensual.toStringAsFixed(0)} × $mesesEnPeriodo meses)' : '';
      return '$cat: gastado \$${gastado.toStringAsFixed(0)} / límite del período \$${limiteEscalado.toStringAsFixed(0)}$escalaStr → $estado';
    }).join('\n');

    final flujoNeto = ingresosProyectados - gastosProyectados;
    final balanceFinal = diasRestantes > 0
        ? () {
            final partes = <String>[];
            if (ingresosProyectados > 0) partes.add('ingresos por cobrar: +\$${ingresosProyectados.toStringAsFixed(0)}');
            if (gastosProyectados > 0) partes.add('gastos comprometidos (cuotas/suscripciones): -\$${gastosProyectados.toStringAsFixed(0)}');
            if (partes.isEmpty) return '';
            final ingresosFinal = totalIngresos + ingresosProyectados;
            final gastosFinal = totalGastos + gastosProyectados;
            final balanceFinalVal = ingresosFinal - gastosFinal;
            return '\nPROYECCIÓN AL CIERRE DEL MES ($diasRestantes días restantes):'
                ' ${partes.join(' | ')}'
                ' → Balance proyectado: \$${balanceFinalVal.toStringAsFixed(0)}'
                ' (flujo neto pendiente: ${flujoNeto >= 0 ? '+' : ''}\$${flujoNeto.toStringAsFixed(0)})';
          }()
        : '';

    // Construir resumen explícito de metas para que la IA no pueda ignorarlas
    final metasResumenExplicito = metas.isEmpty
        ? 'SIN METAS REGISTRADAS'
        : metas.map((m) {
            final nombre = m['nombre'] ?? '';
            final emoji = m['emoji'] != null ? '${m['emoji']} ' : '';
            final actual = (m['montoActual'] as num?)?.toInt() ?? 0;
            final objetivo = (m['montoObjetivo'] as num?)?.toInt() ?? 0;
            final pct = m['progreso_pct'] ?? '0.0';
            return '$emoji$nombre: acumulado \$$actual de \$$objetivo ($pct%)';
          }).join('\n');

    // Ejemplo concreto para el campo ahorro_comentario del JSON
    final ahorroComentarioEjemplo = metas.isEmpty
        ? 'Se aportaron \$${pAhorro.toStringAsFixed(0)} a ahorro general.'
        : 'Se aportaron \$${pAhorro.toStringAsFixed(0)} a metas: '
          + metas.map((m) {
              final nombre = m['nombre'] ?? '';
              final actual = (m['montoActual'] as num?)?.toInt() ?? 0;
              final objetivo = (m['montoObjetivo'] as num?)?.toInt() ?? 0;
              final pct = m['progreso_pct'] ?? '0.0';
              return '$nombre (\$$actual/\$$objetivo, $pct%)';
            }).join(', ') + '.';

    final gastosOperativos = totalGastos - pAhorro;

    final prompt = '''
Eres NEXUS AI. Genera un RESUMEN EJECUTIVO del período con los datos exactos provistos. NO calcules — solo interpreta.

═══ DEFINICIONES OBLIGATORIAS (leer antes de responder) ═══
• AHORRO A METAS (\$${pAhorro.toStringAsFixed(0)}): dinero que el usuario apartó intencionalmente para metas concretas (ver lista abajo). Es un LOGRO, no dinero libre ni parte del excedente disponible.
• GASTOS OPERATIVOS (\$${gastosOperativos.toStringAsFixed(0)}): lo que se gastó en consumo real (sin incluir ahorro).
• BALANCE LIBRE (\$${balanceLibre.toStringAsFixed(0)}): ingresos (\$${totalIngresos.toStringAsFixed(0)}) − gastos totales (\$${totalGastos.toStringAsFixed(0)}) = \$${balanceLibre.toStringAsFixed(0)}. Es el único excedente real disponible.
• NUNCA sumes ahorro + balance libre ni los presentes como un solo número. Son conceptos separados.

═══ METAS DE AHORRO (EXISTEN — NO digas que no hay metas) ═══
        $metasResumenExplicito
REGLA ABSOLUTA: Si la lista de metas de arriba tiene entradas, el usuario SÍ tiene metas definidas y SÍ sabe para qué ahorra. NUNCA escribas "no tienes metas" ni "no sé para qué ahorras".
En ahorro_comentario: menciona cada meta por nombre y cuánto lleva acumulado.

═══ DATOS DEL PERÍODO ═══
PERÍODO: $periodo ($mesesEnPeriodo mes${mesesEnPeriodo > 1 ? 'es' : ''})
- Ingresos: \$${totalIngresos.toStringAsFixed(0)}
- Gastos operativos (consumo real): \$${gastosOperativos.toStringAsFixed(0)}
- Ahorro comprometido a metas: \$${pAhorro.toStringAsFixed(0)}
- Gastos totales (operativos + ahorro): \$${totalGastos.toStringAsFixed(0)}
- Balance libre real: \$${balanceLibre.toStringAsFixed(0)}$clasificacionPeriodo$balanceFinal

GASTOS POR CATEGORÍA: ${catResumen.isEmpty ? 'Sin datos' : catResumen}

${_formatMetas(metas)}

PRESUPUESTOS vs REAL (límite ya escalado a $mesesEnPeriodo mes${mesesEnPeriodo > 1 ? 'es' : ''} — usar tal cual):
${presupuestos.isEmpty ? 'Sin presupuestos' : presupuestosConGasto}

DEUDAS (evaluar por cuotas/impacto mensual, NO por saldo total acumulado):
${deudas.isEmpty ? 'Sin deudas' : deudas.where((d) => d['completada'] != true).map(formatDeudaLinea).join('\n')}
${_formatIngresosEsperados(ingresosEsperados)}${_formatSuscripciones(suscripciones)}
${diasRestantes > 0 ? 'PERÍODO EN CURSO: Quedan $diasRestantes días. Usar la PROYECCIÓN AL CIERRE para puntuación y balance_comentario.' : ''}
- Si alguna deuda tiene "⚡ cuotas adelantadas", menciónalo en logro_destacado como hábito positivo de gestión de flujo de caja.

Responde SOLO con JSON válido:
{
  "titulo": "Título atractivo del período",
  "headline": "Frase resumen — máx 15 palabras",
  "balance_comentario": "El balance libre fue \$${balanceLibre.toStringAsFixed(0)}: cuánto quedó disponible después de todos los gastos y el ahorro. Explica qué significa en contexto. NUNCA menciones ahorro aquí.",
  "ahorro_comentario": "$ahorroComentarioEjemplo",
  "logro_destacado": "Mejor logro concreto del período con montos.",
  "area_atencion": "Riesgo real más importante (omitir deudas al día).",
  "comparacion_habitual": "Mayor/menor/igual vs patrón habitual.",
  "fortalezas": ["Fortaleza con montos concretos", "fortaleza 2"],
  "areas_mejora": ["Área con montos concretos", "área 2"],
  "consejo_siguiente": "Acción concreta para el próximo período.",
  "puntuacion_periodo": 75,
  "emoji_periodo": "🎯"
}
''';

    final json = await _llamarGeminiJson(prompt);
    return json;
  }
}
