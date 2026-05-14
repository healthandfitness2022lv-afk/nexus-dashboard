import '../models/transaccion.dart';
import '../models/deuda.dart';
import '../models/ingreso_esperado.dart';
import '../models/meta.dart';
import '../models/suscripcion.dart';

/// Convierte lista de transacciones al formato resumido para prompts de IA.
List<Map<String, dynamic>> txToMaps(List<Transaccion> lista) =>
    lista
        .map((t) => {
              'tipo': t.tipo.name,
              'descripcion': t.descripcion,
              'monto': t.monto.toInt(),
              'categoria': t.categoria,
              'subcategoria': t.subcategoria,
              'fecha': t.fecha,
              'clasificacion': t.clasificacion?.name,
            })
        .toList();

/// Convierte lista de Deuda al formato resumido para prompts de IA.
List<Map<String, dynamic>> deudasToMaps(List<Deuda> lista) => lista.map((d) {
      final esCorriente = d.esCuentaCorriente;
      final proxima = d.proximaCuotaFija;
      // Cuotas con vencimiento por mes (para que la IA sepa en qué meses cae)
      final cuotasPorMes = <String, double>{};
      for (final c in d.cuotasFijasPendientes) {
        final key = '${c.fechaVencimiento.year}-${c.fechaVencimiento.month.toString().padLeft(2, '0')}';
        cuotasPorMes[key] = (cuotasPorMes[key] ?? 0) + c.monto;
      }

      // Detectar cuotas adelantadas: pagadas antes del mes de su vencimiento
      final cuotasAdelantadas = <Map<String, dynamic>>[];
      if (d.tieneCuotasFijas) {
        for (final abono in d.abonos) {
          if (abono.numeroCuota == null) continue;
          final cuota = d.cuotasFijas
              .where((c) => c.numero == abono.numeroCuota)
              .firstOrNull;
          if (cuota == null) continue;
          // Adelantada si el pago ocurrió antes del mes de vencimiento
          final pagoMes = DateTime(abono.fecha.year, abono.fecha.month);
          final vencMes = DateTime(cuota.fechaVencimiento.year, cuota.fechaVencimiento.month);
          if (pagoMes.isBefore(vencMes)) {
            cuotasAdelantadas.add({
              'numero': cuota.numero,
              'monto': cuota.monto.toInt(),
              'pagadoEl': abono.fecha.toIso8601String(),
              'venciaEl': cuota.fechaVencimiento.toIso8601String(),
              'mesLibre': '${cuota.fechaVencimiento.year}-${cuota.fechaVencimiento.month.toString().padLeft(2, '0')}',
            });
          }
        }
      }

      // Meses que quedan libres de esta deuda por cuotas adelantadas
      final mesesLibres = cuotasAdelantadas.map((c) => c['mesLibre'] as String).toSet().toList()..sort();

      // Cuotas ya pagadas este mes (para que la IA sepa que no hay compromiso pendiente)
      final ahora = DateTime.now();
      final cuotasPagadasEsteMes = <Map<String, dynamic>>[];
      if (d.tieneCuotasFijas) {
        for (final abono in d.abonos) {
          if (abono.numeroCuota == null) continue;
          if (abono.fecha.year != ahora.year || abono.fecha.month != ahora.month) continue;
          final cuota = d.cuotasFijas
              .where((c) => c.numero == abono.numeroCuota)
              .firstOrNull;
          if (cuota == null) continue;
          cuotasPagadasEsteMes.add({
            'numero': cuota.numero,
            'monto': cuota.monto.toInt(),
            'pagadoEl': abono.fecha.toIso8601String(),
            'venciaEl': cuota.fechaVencimiento.toIso8601String(),
          });
        }
      }

      return {
        'descripcion': d.descripcion,
        'tipo': d.tipo.name,
        'modalidad': esCorriente ? 'cuenta_corriente' : 'deuda_fija',
        'montoTotal': d.montoTotal.toInt(),
        'saldoPendiente': d.saldoPendiente.toInt(),
        'totalAbonado': d.totalAbonado.toInt(),
        'totalCargado': esCorriente ? d.totalCargado.toInt() : null,
        'completada': d.completada,
        'vencida': d.vencida,
        'nItems': esCorriente ? d.cargos.length : null,
        'nCuotas': d.tieneCuotasFijas ? d.cuotasFijas.length : null,
        'cuotasPendientes': d.tieneCuotasFijas ? d.cuotasFijasPendientes.length : null,
        'proximaCuota': proxima != null ? {
          'numero': proxima.numero,
          'monto': proxima.monto.toInt(),
          'fechaVencimiento': proxima.fechaVencimiento.toIso8601String(),
        } : null,
        'cuotasPendientesPorMes': cuotasPorMes.map((k, v) => MapEntry(k, v.toInt())),
        'cuotasPagadasEsteMes': cuotasPagadasEsteMes,
        'cuotasAdelantadas': cuotasAdelantadas,
        'mesesLibresPorAdelanto': mesesLibres,
      };
    }).toList();

/// Convierte lista de Meta al formato completo para prompts de IA.
/// NOTA para la IA: cada meta se financia con transacciones de tipo "gasto",
/// categoria "Ahorro", subcategoria igual al nombre de la meta.
List<Map<String, dynamic>> metasToMaps(List<Meta> lista) {
  return lista.map((m) {
    final faltante = m.montoObjetivo - m.montoActual;
    final diasRestantes = m.diasRestantes;
    final mesesRestantes = diasRestantes > 0 ? (diasRestantes / 30).ceil() : 0;
    final ahorroMensualNecesario = mesesRestantes > 0 ? faltante / mesesRestantes : 0.0;
    return {
      'nombre': m.nombre,
      'emoji': m.emoji,
      'montoActual': m.montoActual.toInt(),
      'montoObjetivo': m.montoObjetivo.toInt(),
      'faltante': faltante.clamp(0, double.infinity).toInt(),
      'progreso_pct': (m.progreso * 100).toStringAsFixed(1),
      'completada': m.completada,
      'fechaLimite': m.fechaLimite.toIso8601String(),
      'diasRestantes': diasRestantes,
      'mesesRestantes': mesesRestantes,
      'ahorroMensualNecesario': ahorroMensualNecesario.toInt(),
      // Clave de vinculación: las tx de ahorro usan subcategoria == nombre
      'subcategoria_tx': m.nombre,
    };
  }).toList();
}

/// Resumen preciso de ingresos esperados para inyectar en prompts de IA.
/// [mesPeriodo]: si se pasa, calcula montos relativos a ese mes en lugar de hoy.
List<Map<String, dynamic>> ingresosEsperadosToMaps(
    List<IngresoEsperado> lista, {DateTime? mesPeriodo}) {
  final ref = mesPeriodo ?? DateTime.now();
  final mesRef = DateTime(ref.year, ref.month);
  final mesSig = DateTime(ref.year, ref.month + 1);
  return lista
      .map((i) => {
            'descripcion': i.descripcion,
            'monto_pacto': i.monto.toInt(),
            'frecuencia': i.frecuencia.label,
            'monto_este_mes': i.montoEnMes(mesRef.year, mesRef.month).toInt(),
            'monto_mes_que_viene': i.montoEnMes(mesSig.year, mesSig.month).toInt(),
            'fechaEsperada': i.fechaEsperada.toIso8601String(),
            'esRecurrente': i.esRecurrente,
            'recibido': i.recibido,
          })
      .toList();
}

/// Resumen preciso de suscripciones para inyectar en prompts de IA.
/// [mesPeriodo]: si se pasa, calcula montos relativos a ese mes en lugar de hoy.
List<Map<String, dynamic>> suscripcionesToMaps(List<Suscripcion> lista, {DateTime? mesPeriodo}) {
  final ref = mesPeriodo ?? DateTime.now();
  final mesRef = DateTime(ref.year, ref.month);
  final mesSig = DateTime(ref.year, ref.month + 1);
  return lista
      .map((s) => {
            'descripcion': s.descripcion,
            'monto_pacto': s.monto.toInt(),
            'frecuencia': s.frecuencia.label,
            'monto_este_mes': s.montoEnMes(mesRef.year, mesRef.month).toInt(),
            'monto_mes_que_viene': s.montoEnMes(mesSig.year, mesSig.month).toInt(),
            'fechaInicio': s.fechaInicio.toIso8601String(),
            'pagada_este_mes': s.estaPagadaEn(ref),
          })
      .toList();
}
