/**
 * NEXUS Dashboard API Integration
 * Módulo para conectar el dashboard con datos reales de Firebase/API
 *
 * Uso:
 * 1. Cargar en tu HTML: <script src="dashboard-api-integration.js"></script>
 * 2. Llamar en el dashboard.html script:
 *    const dashboardAPI = new DashboardAPI(firebaseConfig);
 *    dashboardAPI.loadData().then(() => updateDashboard());
 */

class DashboardAPI {
    constructor(firebaseConfig = null) {
        this.firebaseConfig = firebaseConfig;
        this.userId = null;
        this.transacciones = [];
        this.deudas = [];
        this.presupuestos = [];
        this.metas = [];
        this.suscripciones = [];
        this.initialized = false;
    }

    /**
     * Inicializar conexión con Firebase
     */
    async initFirebase() {
        if (!this.firebaseConfig) {
            console.warn('Firebase config no proporcionado. Usando datos locales.');
            return false;
        }

        try {
            // Aquí iría la inicialización de Firebase
            // import { initializeApp } from 'firebase/app';
            // import { getFirestore } from 'firebase/firestore';
            // const app = initializeApp(this.firebaseConfig);
            // this.db = getFirestore(app);

            this.initialized = true;
            return true;
        } catch (error) {
            console.error('Error inicializando Firebase:', error);
            return false;
        }
    }

    /**
     * Cargar todas las transacciones
     */
    async loadTransacciones(userId = null) {
        try {
            if (this.initialized && this.db) {
                // Consulta a Firestore
                // const q = query(collection(this.db, 'usuarios', userId, 'transacciones'),
                //   orderBy('fecha', 'desc'));
                // const snapshot = await getDocs(q);
                // this.transacciones = snapshot.docs.map(doc => ({
                //   id: doc.id,
                //   ...doc.data()
                // }));
            } else {
                // Usar datos locales de localStorage o API local
                const stored = localStorage.getItem('transacciones');
                this.transacciones = stored ? JSON.parse(stored) : [];
            }

            return this.transacciones;
        } catch (error) {
            console.error('Error cargando transacciones:', error);
            return [];
        }
    }

    /**
     * Cargar todas las deudas
     */
    async loadDeudas(userId = null) {
        try {
            if (this.initialized && this.db) {
                // const q = query(collection(this.db, 'usuarios', userId, 'deudas'));
                // const snapshot = await getDocs(q);
                // this.deudas = snapshot.docs.map(doc => ({
                //   id: doc.id,
                //   ...doc.data()
                // }));
            } else {
                const stored = localStorage.getItem('deudas');
                this.deudas = stored ? JSON.parse(stored) : [];
            }

            return this.deudas;
        } catch (error) {
            console.error('Error cargando deudas:', error);
            return [];
        }
    }

    /**
     * Cargar presupuestos
     */
    async loadPresupuestos(userId = null) {
        try {
            if (this.initialized && this.db) {
                // const q = query(collection(this.db, 'usuarios', userId, 'presupuestos'));
                // const snapshot = await getDocs(q);
                // this.presupuestos = snapshot.docs.map(doc => ({
                //   id: doc.id,
                //   ...doc.data()
                // }));
            } else {
                const stored = localStorage.getItem('presupuestos');
                this.presupuestos = stored ? JSON.parse(stored) : [];
            }

            return this.presupuestos;
        } catch (error) {
            console.error('Error cargando presupuestos:', error);
            return [];
        }
    }

    /**
     * Cargar metas
     */
    async loadMetas(userId = null) {
        try {
            if (this.initialized && this.db) {
                // const q = query(collection(this.db, 'usuarios', userId, 'metas'));
                // const snapshot = await getDocs(q);
                // this.metas = snapshot.docs.map(doc => ({
                //   id: doc.id,
                //   ...doc.data()
                // }));
            } else {
                const stored = localStorage.getItem('metas');
                this.metas = stored ? JSON.parse(stored) : [];
            }

            return this.metas;
        } catch (error) {
            console.error('Error cargando metas:', error);
            return [];
        }
    }

    /**
     * Cargar suscripciones
     */
    async loadSuscripciones(userId = null) {
        try {
            if (this.initialized && this.db) {
                // const q = query(collection(this.db, 'usuarios', userId, 'suscripciones'));
                // const snapshot = await getDocs(q);
                // this.suscripciones = snapshot.docs.map(doc => ({
                //   id: doc.id,
                //   ...doc.data()
                // }));
            } else {
                const stored = localStorage.getItem('suscripciones');
                this.suscripciones = stored ? JSON.parse(stored) : [];
            }

            return this.suscripciones;
        } catch (error) {
            console.error('Error cargando suscripciones:', error);
            return [];
        }
    }

    /**
     * Cargar todos los datos en paralelo
     */
    async loadAllData(userId = null) {
        try {
            await Promise.all([
                this.loadTransacciones(userId),
                this.loadDeudas(userId),
                this.loadPresupuestos(userId),
                this.loadMetas(userId),
                this.loadSuscripciones(userId)
            ]);

            return {
                transacciones: this.transacciones,
                deudas: this.deudas,
                presupuestos: this.presupuestos,
                metas: this.metas,
                suscripciones: this.suscripciones
            };
        } catch (error) {
            console.error('Error cargando datos:', error);
            return null;
        }
    }

    /**
     * Calcular estadísticas detalladas
     */
    calcularEstadisticas(transacciones = this.transacciones) {
        const ingresos = transacciones.filter(t => t.tipo === 'ingreso');
        const gastos = transacciones.filter(t => t.tipo === 'gasto');

        const totalIngresos = ingresos.reduce((sum, t) => sum + t.monto, 0);
        const totalGastos = gastos.reduce((sum, t) => sum + t.monto, 0);

        // Por clasificación
        const porClasificacion = {
            necesario: 0,
            innecesario: 0,
            inversion: 0,
            ahorro: 0
        };

        gastos.forEach(t => {
            if (t.clasificacion && porClasificacion.hasOwnProperty(t.clasificacion)) {
                porClasificacion[t.clasificacion] += t.monto;
            }
        });

        // Por categoría
        const porCategoria = {};
        transacciones.forEach(t => {
            if (!porCategoria[t.categoria]) {
                porCategoria[t.categoria] = { ingresos: 0, gastos: 0 };
            }
            if (t.tipo === 'ingreso') {
                porCategoria[t.categoria].ingresos += t.monto;
            } else {
                porCategoria[t.categoria].gastos += t.monto;
            }
        });

        // Tendencias mensuales
        const tendencias = {};
        transacciones.forEach(t => {
            const fecha = new Date(t.fecha);
            const mes = `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}`;

            if (!tendencias[mes]) {
                tendencias[mes] = { ingresos: 0, gastos: 0 };
            }

            if (t.tipo === 'ingreso') {
                tendencias[mes].ingresos += t.monto;
            } else {
                tendencias[mes].gastos += t.monto;
            }
        });

        return {
            totalIngresos,
            totalGastos,
            balance: totalIngresos - totalGastos,
            ratio: totalIngresos > 0 ? ((totalIngresos - totalGastos) / totalIngresos * 100) : 0,
            promedioGastoDiario: totalGastos / Math.max(1, transacciones.length / 30),
            transaccionesTotal: transacciones.length,
            ingresosPromedio: ingresos.length > 0 ? totalIngresos / ingresos.length : 0,
            gastosPromedio: gastos.length > 0 ? totalGastos / gastos.length : 0,
            mayorGasto: Math.max(...gastos.map(t => t.monto), 0),
            mayorIngreso: Math.max(...ingresos.map(t => t.monto), 0),
            porClasificacion,
            porCategoria,
            tendencias
        };
    }

    /**
     * Calcular estado de deudas
     */
    calcularEstadoDeudas(deudas = this.deudas) {
        const resumen = {
            totalDeudado: 0,
            totalAbonado: 0,
            deudaActiva: [],
            deudaCompletada: [],
            proximoVencimiento: null
        };

        deudas.forEach(deuda => {
            resumen.totalDeudado += deuda.saldoPendiente || deuda.montoTotal;
            resumen.totalAbonado += deuda.totalAbonado || 0;

            if (deuda.saldoPendiente > 0 || !deuda.completada) {
                resumen.deudaActiva.push(deuda);
            } else {
                resumen.deudaCompletada.push(deuda);
            }
        });

        // Encontrar próximo vencimiento
        const vencimientos = deudas
            .filter(d => d.cuotasFijas && d.cuotasFijas.length > 0)
            .flatMap(d => d.cuotasFijas.map(c => ({ ...c, deudaId: d.id })))
            .sort((a, b) => new Date(a.fechaVencimiento) - new Date(b.fechaVencimiento));

        if (vencimientos.length > 0) {
            resumen.proximoVencimiento = vencimientos[0];
        }

        return resumen;
    }

    /**
     * Calcular progreso de presupuestos
     */
    calcularPresupuestos(presupuestos = this.presupuestos, transacciones = this.transacciones) {
        return presupuestos.map(presupuesto => {
            const gastos = transacciones
                .filter(t =>
                    t.tipo === 'gasto' &&
                    t.categoria === presupuesto.categoria &&
                    this.enPeriodo(new Date(t.fecha), presupuesto.frecuencia)
                )
                .reduce((sum, t) => sum + t.monto, 0);

            const porcentaje = (gastos / presupuesto.limite) * 100;

            return {
                ...presupuesto,
                gastado: gastos,
                disponible: Math.max(0, presupuesto.limite - gastos),
                porcentaje,
                estado: porcentaje >= 100 ? 'excedido' : porcentaje >= 80 ? 'critico' : 'ok'
            };
        });
    }

    /**
     * Calcular progreso de metas
     */
    calcularMetas(metas = this.metas) {
        return metas.map(meta => ({
            ...meta,
            progreso: (meta.actual / meta.meta) * 100,
            restante: Math.max(0, meta.meta - meta.actual),
            completada: meta.actual >= meta.meta
        }));
    }

    /**
     * Generar insights y recomendaciones
     */
    generarInsights(estadisticas = this.calcularEstadisticas()) {
        const insights = [];

        // Ratio de ahorro
        if (estadisticas.ratio > 30) {
            insights.push({
                tipo: 'success',
                titulo: '¡Ahorro Excelente!',
                mensaje: `Tu ratio de ahorro es ${estadisticas.ratio.toFixed(2)}%. Vas muy bien.`,
                prioridad: 'baja'
            });
        } else if (estadisticas.ratio < 0) {
            insights.push({
                tipo: 'danger',
                titulo: 'Gastos Excesivos',
                mensaje: `Estás gastando más de lo que ganas. Diferencia: $${Math.abs(estadisticas.balance).toFixed(2)}`,
                prioridad: 'alta'
            });
        } else if (estadisticas.ratio < 10) {
            insights.push({
                tipo: 'warning',
                titulo: 'Bajo Margen de Ahorro',
                mensaje: `Tu ratio de ahorro es solo ${estadisticas.ratio.toFixed(2)}%. Considera reducir gastos.`,
                prioridad: 'media'
            });
        }

        // Gastos innecesarios
        const innecesarios = estadisticas.porClasificacion.innecesario;
        const totalGastos = Object.values(estadisticas.porClasificacion).reduce((a, b) => a + b, 0);
        const porcentajeInnecesario = (innecesarios / totalGastos) * 100;

        if (porcentajeInnecesario > 30) {
            insights.push({
                tipo: 'warning',
                titulo: 'Alto Gasto Innecesario',
                mensaje: `${porcentajeInnecesario.toFixed(1)}% de tus gastos son innecesarios ($${innecesarios.toFixed(2)})`,
                prioridad: 'media'
            });
        }

        // Categoría con mayor gasto
        const categorias = Object.entries(estadisticas.porCategoria)
            .map(([cat, datos]) => ({ cat, gasto: datos.gastos }))
            .sort((a, b) => b.gasto - a.gasto);

        if (categorias.length > 0 && categorias[0].gasto > 0) {
            insights.push({
                tipo: 'info',
                titulo: 'Categoría Principal',
                mensaje: `Tu mayor gasto es en "${categorias[0].cat}" ($${categorias[0].gasto.toFixed(2)})`,
                prioridad: 'baja'
            });
        }

        // Gasto promedio diario
        if (estadisticas.promedioGastoDiario > 100) {
            insights.push({
                tipo: 'warning',
                titulo: 'Gasto Diario Elevado',
                mensaje: `Tu gasto promedio diario es $${estadisticas.promedioGastoDiario.toFixed(2)}`,
                prioridad: 'media'
            });
        }

        return insights.sort((a, b) => {
            const prioridades = { alta: 0, media: 1, baja: 2 };
            return prioridades[a.prioridad] - prioridades[b.prioridad];
        });
    }

    /**
     * Exportar datos a CSV
     */
    exportarCSV(tipo = 'transacciones') {
        let datos = [];
        let headers = [];

        switch (tipo) {
            case 'transacciones':
                datos = this.transacciones;
                headers = ['id', 'fecha', 'descripcion', 'monto', 'tipo', 'categoria', 'clasificacion'];
                break;
            case 'deudas':
                datos = this.deudas;
                headers = ['id', 'descripcion', 'montoTotal', 'saldoPendiente', 'totalAbonado'];
                break;
            case 'presupuestos':
                datos = this.presupuestos;
                headers = ['categoria', 'limite', 'frecuencia'];
                break;
            case 'metas':
                datos = this.metas;
                headers = ['nombre', 'meta', 'actual', 'emoji'];
                break;
        }

        let csv = headers.join(',') + '\n';
        datos.forEach(row => {
            csv += headers.map(h => {
                const value = row[h];
                if (typeof value === 'string') {
                    return `"${value}"`;
                }
                return value;
            }).join(',') + '\n';
        });

        const blob = new Blob([csv], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${tipo}_${new Date().toISOString()}.csv`;
        a.click();
        window.URL.revokeObjectURL(url);
    }

    /**
     * Obtener datos formateados para gráficos
     */
    obtenerDatosGrafico(tipo, periodo = 'mes') {
        const transacciones = this.filtrarPorPeriodo(this.transacciones, periodo);

        switch (tipo) {
            case 'balance-diario':
                return this.calcularBalanceDiario(transacciones);
            case 'ingresos-gastos':
                return this.calcularIngresosGastos(transacciones);
            case 'por-categoria':
                return this.calcularPorCategoria(transacciones);
            case 'por-clasificacion':
                return this.calcularPorClasificacion(transacciones);
            case 'tendencias':
                return this.calcularTendencias(transacciones);
            default:
                return null;
        }
    }

    // Métodos auxiliares privados
    enPeriodo(fecha, frecuencia) {
        const ahora = new Date();
        const diasAtras = frecuencia === 'semanal' ? 7 : frecuencia === 'quincenal' ? 14 : 30;
        const fechaLimite = new Date(ahora.getTime() - diasAtras * 24 * 60 * 60 * 1000);
        return fecha >= fechaLimite;
    }

    filtrarPorPeriodo(transacciones, periodo) {
        const ahora = new Date();
        let fechaInicio = new Date();

        switch (periodo) {
            case 'dia':
                fechaInicio.setHours(0, 0, 0, 0);
                break;
            case 'semana':
                fechaInicio.setDate(ahora.getDate() - ahora.getDay());
                break;
            case 'mes':
                fechaInicio.setDate(1);
                break;
            case 'año':
                fechaInicio.setMonth(0, 1);
                break;
            case 'todo':
                fechaInicio = new Date(0);
                break;
        }

        return transacciones.filter(t => new Date(t.fecha) >= fechaInicio);
    }

    calcularBalanceDiario(transacciones) {
        const datos = {};
        let balance = 0;

        transacciones
            .sort((a, b) => new Date(a.fecha) - new Date(b.fecha))
            .forEach(t => {
                const fecha = new Date(t.fecha).toLocaleDateString('es-ES');
                balance += (t.tipo === 'ingreso' ? t.monto : -t.monto);
                datos[fecha] = balance;
            });

        return {
            labels: Object.keys(datos),
            data: Object.values(datos)
        };
    }

    calcularIngresosGastos(transacciones) {
        const ingresos = transacciones
            .filter(t => t.tipo === 'ingreso')
            .reduce((sum, t) => sum + t.monto, 0);

        const gastos = transacciones
            .filter(t => t.tipo === 'gasto')
            .reduce((sum, t) => sum + t.monto, 0);

        return {
            labels: ['Ingresos', 'Gastos'],
            data: [ingresos, gastos]
        };
    }

    calcularPorCategoria(transacciones) {
        const categorias = {};

        transacciones.forEach(t => {
            if (!categorias[t.categoria]) {
                categorias[t.categoria] = 0;
            }
            categorias[t.categoria] += t.monto;
        });

        return {
            labels: Object.keys(categorias),
            data: Object.values(categorias)
        };
    }

    calcularPorClasificacion(transacciones) {
        const clasificaciones = {
            necesario: 0,
            innecesario: 0,
            inversion: 0,
            ahorro: 0
        };

        transacciones
            .filter(t => t.tipo === 'gasto')
            .forEach(t => {
                if (t.clasificacion && clasificaciones.hasOwnProperty(t.clasificacion)) {
                    clasificaciones[t.clasificacion] += t.monto;
                }
            });

        return {
            labels: Object.keys(clasificaciones),
            data: Object.values(clasificaciones)
        };
    }

    calcularTendencias(transacciones) {
        const meses = {};

        transacciones.forEach(t => {
            const fecha = new Date(t.fecha);
            const mes = fecha.toLocaleDateString('es-ES', { year: 'numeric', month: 'long' });

            if (!meses[mes]) {
                meses[mes] = { ingresos: 0, gastos: 0 };
            }

            if (t.tipo === 'ingreso') {
                meses[mes].ingresos += t.monto;
            } else {
                meses[mes].gastos += t.monto;
            }
        });

        return {
            labels: Object.keys(meses),
            ingresos: Object.values(meses).map(m => m.ingresos),
            gastos: Object.values(meses).map(m => m.gastos)
        };
    }
}

// Exportar para uso en módulos
if (typeof module !== 'undefined' && module.exports) {
    module.exports = DashboardAPI;
}