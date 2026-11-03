%% ANALISIS TFM (LCA): EMG + IMU + MVC - MEDIA POR EJERCICIO  (v3.2, P5)
%
% LADO OPERADO DE P5: IZQUIERDO.
% PARA OTRO PACIENTE: cambiar paciente, ladoOperado, archivosTarea, archivosMVC y modoSegmentacion.
clear; clc; close all;

%% ============================================================
% 1. CONFIGURACION GENERAL
% =============================================================
paciente    = 'P5';
ladoOperado = 'I';          % <<< 'I': lado de la rodilla intervenida (VERIFICAR en P5)

mvcManual = struct();       % ej.: mvcManual.VM_I = 150;  (en uV RMS)

FsEMG = 2000; fLow = 20; fHigh = 450; ventanaRMS_s = 0.250;

archivosTarea = {'S1.csv','S2.csv','S3.csv', ...
                 'ED1.csv','ED2.csv','ED3.csv', ...
                 'EI1.csv','EI2.csv','EI3.csv'};

nombreEjercicio = containers.Map( ...
    {'S',                  'ED',               'EI'}, ...
    {'Sentarse-levantarse','Ejercicio ED',     'Ejercicio EI'});

% Senal de segmentacion: 'ambas' | 'D' | 'I' (rodilla) | 'HD' | 'HI' (cadera) | 'VLD' | 'VLI' (EMG del VL)
% Si la rodilla pedida no tiene senal, se usa la del otro lado (se avisa en consola).
% EI en P5: la rodilla I no existe => se segmenta con la rodilla D (pierna de APOYO en EI).
% Si EI sale mal, probar 'HD' (cadera D) o 'VLI' (EMG del vasto lateral I).
modoSegmentacion = containers.Map({'S','ED','EI'},{'ambas','D','I'});

% Deteccion automatica del reposo
ventanaReposo_s  = 1.5;
busquedaReposo_s = 10;
reposoManual = containers.Map('KeyType','char','ValueType','any');   % ej.: reposoManual('S3.csv') = [3 5];
% P5, A REVISAR: el reposo automatico de S3 (7,86-9,36 s), EI1 (3,22-4,72 s) y EI2 (2,44-3,94 s) parece caer
% en pleno movimiento segun las figuras. Fijar una ventana estatica de pie con reposoManual si se confirma.

ejePorArchivo = true;
maxHuecoQ_s   = 1.0;

% Calidad de datos
maxVelArticular_dps = 800;
minValidoLado       = 0.5;
marcarHuecosEMG     = true;
excluirLado = containers.Map('KeyType','char','ValueType','any'); % ej.: excluirLado('S2.csv') = 'D';

% Musculos sin MVC valido (MVC < fracMinMVCvsTarea x pico de la tarea):
%   false (v3) = se normalizan al pico de la tarea (NO es %MVC real) y quedan con Calidad 0 en el resumen global
%   true       = se excluyen (NaN)
ocultarMusculosSinMVC = false;
% Muestras de EMG por encima de este %MVC se descartan como artefacto (Inf = no descartar nada)
limiteArtefactoEMG_pct = 150;     % P5: activo por las mesetas de BF D (Inf = no descartar nada)
% P5: BF D tiene "mesetas" rectangulares de 260-470 %MVC en S y EI (artefacto, no EMG). Con un limite
% (p. ej. 150) esas muestras pasan a NaN y la repeticion se anula si pierde > 5 %. Decidir tras mirar
% la senal cruda (columna 14 de S2.csv entre 4,5 y 6,5 s): activar diagnosticoBF_D mas abajo.
% OJO: este limite solo quita las mesetas grandes; las de 75-140 %MVC siguen inflando el pico de BF D.

% Intervalo activo
umbralMovimiento_deg    = 8;
duracionMinMovimiento_s = 0.25;
rellenoHuecos_s         = 0.20;

% Repeticiones
distanciaMinPicos_s  = 0.8;
% Distancia minima entre picos por ejercicio (s). Dejar 0,8 y subir SOLO si Duracion_rep_s de un
% ejercicio sale la mitad que en los demas (doble conteo; en P2 'EI' hizo falta 2,2 s).
distanciaMinPicosEj = containers.Map({'S','ED','EI'},{0.8,0.8,0.8});
% Relleno (s) que se anade al final del intervalo activo SOLO para segmentar (si el valle final de la
% ultima repeticion queda fuera porque la rodilla baja de 8 grados). Subir solo si se ve en la figura.
% P5 (v3.2): con 0 se perdia la ULTIMA repeticion en S3, ED3, EI1... (el valle final queda fuera del
% intervalo activo). Se pone 1,0 en los tres ejercicios; comprobar en las figuras que no se cuela nada.
padFinalSeg_s = containers.Map({'S','ED','EI'},{1.0,1.0,1.0});
% Se descartan repeticiones con duracion < fracDurMinRep x mediana de su archivo (fragmentos)
fracDurMinRep = 0.5;
% Solo modos 'VLD'/'VLI' (EMG): prominencia minima (%MVC), fraccion de la prominencia maxima y tolerancia
promMinVL_pct = 15;  fracPromVL = 0.35;  tolCentrado = 0.25;
prominenciaMin_deg   = 8;
fraccionProminencia  = 0.5;
% Fraccion de la prominencia maxima por ejercicio (subir en EI si siguen apareciendo movimientos
% preparatorios pequenos como repeticiones; en P5 EI1/EI2 la 1.a repeticion es un pico de ~36-45 grados
% frente a ~65 de las demas).
fraccionProminenciaEj = containers.Map({'S','ED','EI'},{0.5,0.5,0.65});
incluirRepIncompleta = false;
nPuntos = 101;

% Desfase izquierda-derecha (solo ejercicios simetricos). En P5 no hay cinematica I: no se aplica.
alinearLados         = true;
ejerciciosSimetricos = {'S'};
maxLagLados_s        = 4.5;
umbralValidezAlinear = 0.8;
minLagCorregir_s     = 0.10;   % no se corrige si |lag| es menor
minMejoraCorr        = 0.05;   % la correlacion D-I debe mejorar al menos esto tras alinear

% Exclusion manual de repeticiones por ventana temporal (s), por archivo
excluirVentana = containers.Map('KeyType','char','ValueType','any');   % ej.: excluirVentana('EI2.csv') = [5 10.5];
% P5, CANDIDATOS (VERIFICAR en las figuras de movimiento real antes de activar):
excluirVentana('S2.csv')  = [2 6.6];   % 1.a rep (2,10-6,57 s, 4,47 s) = pequenos picos previos (~45 grados), no es una sentada completa
% excluirVentana('EI1.csv') = [0 3.5];   % 1.a rep (1,24-3,18 s) = movimiento preparatorio (~36 grados)
% ROM de una articulacion que se descarta en un archivo (la senal sigue en el EMG y en las figuras de
% movimiento real, pero se anula en el ROM por repeticion y en las curvas medias).
% Valores: 'hipD','hipI','kneeD','kneeI'.
excluirROM = containers.Map('KeyType','char','ValueType','any');       % ej.: excluirROM('S3.csv') = {'kneeD'};
% P5 (v3.2): eje de cadera D no fiable (|cos con el global| 0,09-0,37; deriva visible en las figuras)
excluirROM('S2.csv')  = {'hipD'};
excluirROM('ED2.csv') = {'hipD'};
excluirROM('EI2.csv') = {'hipD'};
excluirROM('EI3.csv') = {'hipD'};

recorteManual = containers.Map('KeyType','char','ValueType','any');

% MVC
fracMinEnsayoMVC  = 0.05;
fracMinMVCvsTarea = 0.02;
% Calidad
umbralNoInterpEje = 0.60;
umbralEje         = 0.85;
fracRepsSobre100  = 0.20;
nMinROM           = 5;     % n efectivo minimo de repeticiones validas (operada y sana) para que el ROM tenga calidad > 0
umbralCanalPlano_pct = 5;  % pico (%MVC) por debajo del cual un lado se considera SIN SENAL en toda la tarea
ejeArchivoAnulaCalidad = false;  % true: eje por archivo <60 % => calidad ROM 0 (false: tope 1)
% Ajustes manuales de calidad: clave 'Variable|Tarea' (Tarea = 'S' o 'Step'), valor 0/1/2
calidadManual = containers.Map('KeyType','char','ValueType','double');

% Diagnosticos opcionales (apagados por defecto)
diagnosticoMVC_GM = false;   % true: imprime el RMS maximo de TODAS las columnas EMG de GMI1-3 y GMD1-3
diagnosticoBF_D   = false;   % true: dibuja la senal cruda y el RMS de BF D en S2.csv (4,5-6,5 s)

% Figuras
figurasPorArchivo        = false;
figurasMovimientoReal    = true;
figurasMediaPorEjercicio = true;
figurasComparacion       = true;
mostrarFigurasEnPantalla = false;
crearFigurasVisibles     = false;   % pon true si las figuras salen en blanco
setappdata(0,'visFig',ifelse(crearFigurasVisibles,'on','off'));
carpetaFiguras           = [paciente '_figuras'];
if ~isfolder(carpetaFiguras), mkdir(carpetaFiguras); end

%% ============================================================
% 2. MUSCULOS Y COLUMNAS
% =============================================================
musculos = {'VM_D','VL_D','VM_I','VL_I','GM_D','GM_I','BF_D','BF_I'};
nombreMusculo = containers.Map(musculos, { ...
    'Vasto medial D','Vasto lateral D','Vasto medial I','Vasto lateral I', ...
    'Glúteo medio D','Glúteo medio I','Isquiotibiales D (bíceps femoral)', ...
    'Isquiotibiales I (bíceps femoral)'});

paresBase   = {'VM','VL','GM','BF'};
nombreBase  = {'Vasto medial','Vasto lateral','Glúteo medio','Isquiotibiales'};

% CSV de 49 columnas: 8 nodos con 2 canales EMG + 4 de cuaternion
%  nodo1 (2-7): GM D | nodo2 (8-13): VM D, VL D | nodo3 (14-19): BF D
%  nodo4 (20-25): GM I | nodo5 (26-31): tibia D | nodo6 (32-37): VM I, VL I
%  nodo7 (38-43): tibia I | nodo8 (44-49): BF I
col.GM_D = 2;  col.VM_D = 8;  col.VL_D = 9;  col.BF_D = 14;
col.GM_I = 20; col.VM_I = 32; col.VL_I = 33; col.BF_I = 44;
col.qS1 = 4:7;   % pelvis derecha
col.qS2 = 10:13; % muslo derecho
col.qS4 = 22:25; % pelvis izquierda
col.qS5 = 28:31; % tibia derecha
col.qS6 = 34:37; % muslo izquierdo   (en P5 VACIO en todas las tareas)
col.qS7 = 40:43; % tibia izquierda

% Columna de EMG usada en los ensayos de MVC (por defecto, la misma que en las tareas).
% P5: GMI1-3 tienen la columna 20 VACIA. HIPOTESIS a comprobar: el electrodo del GM se grabo en el
% nodo 1 (columna 2) tambien en los ensayos del lado I. Activar diagnosticoMVC_GM para ver en que
% columna hay senal y, si es la 2, descomentar la linea siguiente.
colMVC = col;
% colMVC.GM_I = 2;

vars = {'hipFlexD','hipFlexI','kneeFlexD','kneeFlexI', ...
        'VM_D','VL_D','VM_I','VL_I','GM_D','GM_I','BF_D','BF_I'};
% Correspondencia variable angular -> clave de excluirROM
mapaVarROM = containers.Map({'hipFlexD','hipFlexI','kneeFlexD','kneeFlexI'}, ...
                            {'hipD','hipI','kneeD','kneeI'});

%% ============================================================
% 3. MVC (valores por ensayo, ya en uV)
% =============================================================
archivosMVC.GM_D = {'GMD1.csv','GMD2.csv','GMD3.csv'};
archivosMVC.GM_I = {'GMI1.csv','GMI2.csv','GMI3.csv'};
archivosMVC.BF_D = {'ID1.csv','ID2.csv','ID3.csv'};
archivosMVC.BF_I = {'II1.csv','II2.csv','II3.csv'};
archivosMVC.CUAD = {'MVC1.csv','MVC2.csv','MVC3.csv'};

if diagnosticoMVC_GM
    fprintf('\n=== DIAGNOSTICO: RMS maximo (uV) por columna EMG en los ensayos de MVC de GM ===\n');
    colsEMG = reshape([2:6:44; 3:6:45],1,[]);
    for f = [archivosMVC.GM_I archivosMVC.GM_D]
        d = cargarCSV(f{1});
        if isempty(d), fprintf('%s: no se pudo leer\n',f{1}); continue; end
        mx = NaN(size(colsEMG));
        for ic = 1:numel(colsEMG)
            y = procesarEMG(d(:,colsEMG(ic)),FsEMG,fLow,fHigh,ventanaRMS_s);
            mx(ic) = max(y,[],'omitnan');
        end
        fprintf('%s: ',f{1}); fprintf('c%d=%.1f  ',[colsEMG; mx]); fprintf('\n');
    end
end

fprintf('\n=== MVC %s ===\n',paciente);
mvc = struct(); mvcOrigen = struct(); mvcInfo = struct();
for j = 1:numel(musculos)
    m = musculos{j};
    if startsWith(m,'VM') || startsWith(m,'VL'), lista = archivosMVC.CUAD; else, lista = archivosMVC.(m); end
    [mvc.(m),mvcInfo.(m)] = calcularMVC(lista,colMVC.(m),FsEMG,fLow,fHigh,ventanaRMS_s,fracMinEnsayoMVC,m);
    mvcOrigen.(m) = "MVC";
end

%% ============================================================
% 4. FASE 1: PROCESAR CADA ARCHIVO
% =============================================================
SIG = {}; filasUni = [];
nomSensor = {'pelvis D','muslo D','tibia D','pelvis I','muslo I','tibia I'};
for ia = 1:numel(archivosTarea)
    archivo = archivosTarea{ia};
    if ~isfile(archivo), warning('No se encuentra %s; se omite.',archivo); continue; end
    fprintf('\n=== Procesando %s ===\n',archivo);
    datos = cargarCSV(archivo);
    if isempty(datos) || size(datos,2) < 49
        warning('%s no tiene 49 columnas numéricas legibles.',archivo); continue;
    end
    tiempo = datos(:,1);
    Fs = 1/median(diff(tiempo),'omitnan');
    fprintf('Muestras=%d, duración=%.2f s, Fs=%.1f Hz\n',size(datos,1),tiempo(end)-tiempo(1),Fs);
    if abs(Fs-FsEMG) > 1
        warning('%s: Fs del archivo (%.1f Hz) distinta de FsEMG (%d Hz). Revisar.',archivo,Fs,FsEMG);
    end

    [~,base] = fileparts(archivo);
    ej = regexprep(base,'\d+[A-Za-z]?$','');

    if diagnosticoBF_D && strcmp(archivo,'S2.csv')
        xr = armonizarUnidadEMG(double(datos(:,col.BF_D)));
        fDiag = figure('Name','Diagnostico BF D - S2','Color','w');
        tiledlayout(fDiag,2,1);
        nexttile; plot(tiempo,xr); xlim([4.5 6.5]); grid on; ylabel('uV (crudo)');
        title('BF D, S2.csv: señal cruda');
        nexttile; plot(tiempo,procesarEMG(datos(:,col.BF_D),FsEMG,fLow,fHigh,ventanaRMS_s)); xlim([4.5 6.5]);
        grid on; ylabel('RMS (uV)'); xlabel('Tiempo (s)'); title('BF D, S2.csv: envolvente RMS');
    end

    rmsEMG = struct();
    for j = 1:numel(musculos)
        m = musculos{j};
        [rmsEMG.(m),uni] = procesarEMG(datos(:,col.(m)),FsEMG,fLow,fHigh,ventanaRMS_s,marcarHuecosEMG);
        filasUni = [filasUni; struct('Archivo',string(archivo),'Musculo',string(m),'Unidad_original',string(uni))]; %#ok<AGROW>
        pn = 100*mean(isnan(rmsEMG.(m)));
        if pn > 1, fprintf('  Aviso EMG: %s con %.1f %% de muestras perdidas (huecos > 50 ms o canal sin señal)\n',nombreMusculo(m),pn); end
    end

    qP_D = limpiarQ(datos(:,col.qS1),Fs,maxHuecoQ_s); qM_D = limpiarQ(datos(:,col.qS2),Fs,maxHuecoQ_s); qT_D = limpiarQ(datos(:,col.qS5),Fs,maxHuecoQ_s);
    qP_I = limpiarQ(datos(:,col.qS4),Fs,maxHuecoQ_s); qM_I = limpiarQ(datos(:,col.qS6),Fs,maxHuecoQ_s); qT_I = limpiarQ(datos(:,col.qS7),Fs,maxHuecoQ_s);

    Qall = {qP_D,qM_D,qT_D,qP_I,qM_I,qT_I};
    pctInvSensor = zeros(1,6);
    for k = 1:6, pctInvSensor(k) = 100*mean(~all(isfinite(Qall{k}),2)); end
    if any(pctInvSensor > 1)
        fprintf('  %% no válido por sensor (pelvis D, muslo D, tibia D, pelvis I, muslo I, tibia I): %s\n', ...
            sprintf('%.1f ',pctInvSensor));
    end

    restD = detectarReposo({qP_D,qM_D,qT_D},Fs,ventanaReposo_s,busquedaReposo_s);
    restI = detectarReposo({qP_I,qM_I,qT_I},Fs,ventanaReposo_s,busquedaReposo_s);
    if isKey(reposoManual,archivo)
        rc = reposoManual(archivo);
        restD = tiempo >= rc(1) & tiempo <= rc(2); restI = restD;
        fprintf('  Reposo MANUAL: %.2f - %.2f s\n',rc(1),rc(2));
    end
    wD = ventanaT(tiempo,restD); wI = ventanaT(tiempo,restI);
    fprintf('  Reposo D: %.2f - %.2f s | Reposo I: %.2f - %.2f s\n',wD(1),wD(2),wI(1),wI(2));

    rv = struct();
    rv.hipD  = rotvecRel(qP_D,qM_D,restD);  rv.hipI  = rotvecRel(qP_I,qM_I,restI);
    rv.kneeD = rotvecRel(qM_D,qT_D,restD);  rv.kneeI = rotvecRel(qM_I,qT_I,restI);

    sig = struct('archivo',archivo,'base',base,'ejercicio',ej,'t',tiempo,'Fs',Fs);
    sig.rms = rmsEMG; sig.rv = rv; sig.restD = restD; sig.restI = restI; sig.pctInvSensor = pctInvSensor;
    SIG{end+1} = sig; %#ok<SAGROW>
end
if isempty(SIG), error('No se ha procesado ningún archivo.'); end
writetable(struct2table(filasUni),[paciente '_unidades_EMG_originales.csv']);

%% ============================================================
% 5. EJES DE FLEXO-EXTENSION (SVD) - GLOBAL y POR ARCHIVO
% =============================================================
fprintf('\n=== Ejes de flexión-extensión ===\n');
jn = {'hipD','hipI','kneeD','kneeI'};
eje = struct(); varExpl = struct(); filasEje = [];
for j = 1:numel(jn)
    X = []; Xs = [];
    for is = 1:numel(SIG)
        r = SIG{is}.rv.(jn{j});
        r = r(all(isfinite(r),2) & sqrt(sum(r.^2,2)) > 5,:);
        r = r(1:10:end,:);
        X = [X; r]; %#ok<AGROW>
        if strcmp(SIG{is}.ejercicio,'S'), Xs = [Xs; r]; end %#ok<AGROW>
    end
    if size(X,1) < 50
        warning('Articulación %s SIN datos suficientes de movimiento: quedará en NaN.',jn{j});
        eje.(jn{j}) = [NaN NaN NaN]; varExpl.(jn{j}) = NaN;
        filasEje = [filasEje; filaEje("GLOBAL",jn{j},[NaN NaN NaN],NaN,NaN,false,"sin datos",NaN)]; %#ok<AGROW>
        continue;
    end
    [~,S,V] = svd(X,'econ');
    ax = V(:,1);
    expl = S(1,1)^2/sum(diag(S).^2);
    varExpl.(jn{j}) = expl;
    if startsWith(jn{j},'hip') && size(Xs,1) > 50, Xref = Xs; else, Xref = X; end
    P = Xref*ax;
    if prctile(P,99) < -prctile(P,1), ax = -ax; end
    eje.(jn{j}) = ax(:)';
    fprintf('GLOBAL %s: eje=[% .2f % .2f % .2f], varianza explicada=%.0f %%\n',jn{j},ax,100*expl);
    filasEje = [filasEje; filaEje("GLOBAL",jn{j},ax(:)',expl,1,false,"global",NaN)]; %#ok<AGROW>
end

ordenJ = {'kneeD','kneeI','hipD','hipI'};
ejeArch = cell(numel(SIG),1);
for is = 1:numel(SIG)
    ejeArch{is} = struct(); angK = struct();
    for jj = 1:numel(ordenJ)
        jname = ordenJ{jj};
        rfull = SIG{is}.rv.(jname);
        r = rfull(all(isfinite(rfull),2) & sqrt(sum(rfull.^2,2)) > 5,:);
        r = r(1:10:end,:);
        axg = eje.(jname); expl = NaN; rho = NaN; metodo = 'global';
        amb = false; a99 = NaN; a1 = NaN;
        if ejePorArchivo && size(r,1) >= 30
            [~,S,V] = svd(r,'econ');
            ax = V(:,1)'; expl = S(1,1)^2/sum(diag(S).^2);
            P = r*ax';
            if startsWith(jname,'hip')
                K = angK.(['knee' jname(end)]);
                H = rfull*ax';
                ok = isfinite(K) & isfinite(H) & (abs(K) > 5 | abs(H) > 5);
                if nnz(ok) > 200
                    cc = corrcoef(H(ok),K(ok)); rho = cc(1,2);
                end
            end
            % NOTA: rho se calcula ANTES de decidir el signo (si rho < 0 el eje se invierte)
            if isfinite(rho) && abs(rho) > 0.2
                if rho < 0, ax = -ax; end
                metodo = 'corr rodilla';
            else
                if prctile(P,99) < -prctile(P,1), ax = -ax; end
                metodo = 'excursión';
            end
            P = r*ax'; a99 = prctile(P,99); a1 = -prctile(P,1);
            amb = strcmp(metodo,'excursión') && min(a99,a1) > 0.6*max(a99,a1);
            if expl < umbralEje
                warning('%s %s: solo %.0f %% de la rotación va en un eje (revisar sensores/huecos).', ...
                    SIG{is}.archivo,jname,100*expl);
            end
            if amb
                warning('%s %s: signo AMBIGUO (excursión +%.0f° / -%.0f°). Revisa la gráfica.', ...
                    SIG{is}.archivo,jname,a99,a1);
            end
        else
            ax = axg;
        end
        ejeArch{is}.(jname) = ax;
        if startsWith(jname,'knee'), angK.(jname) = rfull*ax'; end
        dotG = abs(dot(ax,axg));
        fprintf('%-8s %-6s eje=[% .2f % .2f % .2f] var=%3.0f %% |cos global|=%.2f signo: %s (rho cad-rod=%.2f)\n', ...
            SIG{is}.archivo,jname,ax,100*expl,dotG,metodo,rho);
        filasEje = [filasEje; filaEje(string(SIG{is}.archivo),jname,ax,expl,dotG,amb,string(metodo),rho)]; %#ok<AGROW>
    end
end
tablaEjes = struct2table(filasEje);
writetable(tablaEjes,[paciente '_ejes_articulares.csv']);

%% ============================================================
% 6. ANGULOS + CALIDAD + INTERVALO ACTIVO
% =============================================================
for is = 1:numel(SIG)
    s = SIG{is}; Fs = s.Fs;
    nSmooth = max(1,round(0.05*Fs));
    ang = struct();
    for j = 1:numel(jn)
        a = s.rv.(jn{j})*ejeArch{is}.(jn{j})';
        a = movmean(a,nSmooth,'omitnan');
        if endsWith(jn{j},'D'), rr = s.restD; else, rr = s.restI; end
        off = median(a(rr),'omitnan'); if ~isfinite(off), off = 0; end
        a = a - off;
        [a,nSal,iSal] = limpiarSaltos(a,Fs,maxVelArticular_dps);
        if nSal > 0
            fprintf('  %s %s: %d salto(s) artificial(es) en t = %s s -> descartado\n', ...
                s.archivo,jn{j},nSal,sprintf('%.1f ',s.t(iSal)));
        end
        ang.(jn{j}) = a;
    end
    s.hipFlexD = ang.hipD; s.hipFlexI = ang.hipI;
    s.kneeFlexD = ang.kneeD; s.kneeFlexI = ang.kneeI;
    s = rmfield(s,'rv');

    [i1,i2] = intervaloActivo(s.kneeFlexD,s.kneeFlexI,Fs,umbralMovimiento_deg,rellenoHuecos_s,duracionMinMovimiento_s);
    fD = mean(isfinite(s.kneeFlexD(i1:i2))); fI = mean(isfinite(s.kneeFlexI(i1:i2)));
    exD = false; exI = false;
    if isKey(excluirLado,s.archivo)
        ex = excluirLado(s.archivo); exD = contains(ex,'D'); exI = contains(ex,'I');
    end
    if exD || fD < minValidoLado
        if any(isfinite(s.kneeFlexD)) || any(isfinite(s.hipFlexD))
            warning('%s: lado DERECHO (IMU) excluido (válido %.0f %%).',s.archivo,100*fD);
        else
            fprintf('  %s: lado DERECHO sin cinemática (IMU).\n',s.archivo);
        end
        s.hipFlexD(:) = NaN; s.kneeFlexD(:) = NaN; fD = 0;
    end
    if exI || fI < minValidoLado
        if any(isfinite(s.kneeFlexI)) || any(isfinite(s.hipFlexI))
            warning('%s: lado IZQUIERDO (IMU) excluido (válido %.0f %%).',s.archivo,100*fI);
        else
            fprintf('  %s: lado IZQUIERDO sin cinemática (IMU).\n',s.archivo);
        end
        s.hipFlexI(:) = NaN; s.kneeFlexI(:) = NaN; fI = 0;
    end
    fprintf('%s: datos válidos en zona activa D=%.0f %%, I=%.0f %%\n',s.archivo,100*fD,100*fI);

    % --- desfase izquierda-derecha
    if min(fD,fI) > 0.2
        s.lagIzq = lagIzqVsDer(s.kneeFlexD,s.kneeFlexI,Fs,maxLagLados_s);
    else
        s.lagIzq = 0;
    end
    s.lagBruto = s.lagIzq; s.alineado = false;
    fprintf('%s: lag rodilla I vs D = %+.2f s (>0 = izquierda retrasada)\n',s.archivo,s.lagIzq);
    if abs(s.lagIzq) >= 0.95*maxLagLados_s
        warning('%s: |lag| en el límite de búsqueda (%.1f s). Desfase no fiable.',s.archivo,maxLagLados_s);
    end
    if alinearLados && any(strcmp(s.ejercicio,ejerciciosSimetricos))
        if min(fD,fI) < umbralValidezAlinear
            s.lagIzq = 0;
        elseif abs(s.lagIzq) < minLagCorregir_s
            fprintf('   -> lag < %.2f s: no se corrige\n',minLagCorregir_s); s.lagIzq = 0;
        else
            c0 = corrDI(s.kneeFlexD,s.kneeFlexI);
            desf = @(y) interp1(s.t,y,s.t + s.lagIzq,'linear',NaN);
            c1 = corrDI(s.kneeFlexD,desf(s.kneeFlexI));
            if ~(c1 > c0 + minMejoraCorr)
                fprintf('   -> alinear no mejora la coincidencia D-I (%.2f -> %.2f): NO se corrige\n',c0,c1); s.lagIzq = 0;
            else
                s.hipFlexI = desf(s.hipFlexI); s.kneeFlexI = desf(s.kneeFlexI);
                for mm = {'VM_I','VL_I','GM_I','BF_I'}, s.rms.(mm{1}) = desf(s.rms.(mm{1})); end
                s.alineado = true;
                fprintf('   -> señal izquierda alineada con la derecha (%+.2f s; correlación D-I %.2f -> %.2f)\n',s.lagIzq,c0,c1);
            end
        end
    else
        s.lagIzq = 0;
    end

    % lag ORIENTATIVO por envolvente del cuadriceps cuando no hay cinematica de ambos lados (NO se aplica)
    s.lagEMG = NaN;
    if any(strcmp(s.ejercicio,ejerciciosSimetricos)) && min(fD,fI) < umbralValidezAlinear
        eD = mean([s.rms.VM_D s.rms.VL_D],2,'omitnan'); eI = mean([s.rms.VM_I s.rms.VL_I],2,'omitnan');
        if any(isfinite(eD)) && any(isfinite(eI))
            s.lagEMG = lagIzqVsDer(eD,eI,Fs,maxLagLados_s);
            fprintf('%s: lag ORIENTATIVO por EMG de cuádriceps I vs D = %+.2f s (NO se aplica)\n',s.archivo,s.lagEMG);
        end
    end

    mx = max(abs([s.hipFlexD; s.hipFlexI; s.kneeFlexD; s.kneeFlexI]),[],'omitnan');
    if ~isempty(mx) && isfinite(mx) && mx > 180, warning('%s: ángulo > 180° (%.0f°). Revisar sensores.',s.archivo,mx); end

    [s.iStart,s.iEnd] = intervaloActivo(s.kneeFlexD,s.kneeFlexI,Fs,umbralMovimiento_deg,rellenoHuecos_s,duracionMinMovimiento_s);
    if isKey(recorteManual,s.archivo)
        rc = recorteManual(s.archivo);
        s.iStart = find(s.t >= rc(1),1,'first'); s.iEnd = find(s.t <= rc(2),1,'last');
        fprintf('%s: recorte manual %.1f - %.1f s\n',s.archivo,rc(1),rc(2));
    end
    ii = s.iStart:s.iEnd;
    s.pctValido = 100*[mean(isfinite(s.hipFlexD(ii))) mean(isfinite(s.hipFlexI(ii))) ...
                       mean(isfinite(s.kneeFlexD(ii))) mean(isfinite(s.kneeFlexI(ii)))];
    SIG{is} = s;
end

%% ============================================================
% 7. MVC DEFINITIVO Y %MVC
% =============================================================
fprintf('\n=== Validación del MVC frente a las tareas ===\n');
nArtefacto = struct();
for j = 1:numel(musculos), nArtefacto.(musculos{j}) = 0; end
for j = 1:numel(musculos)
    m = musculos{j};
    picoTarea = 0;
    for is = 1:numel(SIG), picoTarea = max(picoTarea,prctile(SIG{is}.rms.(m),99.9)); end
    if isfield(mvcManual,m) && ~isempty(mvcManual.(m))
        fprintf('MVC %s sustituido manualmente: %.5g -> %.5g\n',m,mvc.(m),mvcManual.(m));
        mvc.(m) = mvcManual.(m); mvcOrigen.(m) = "Manual";
    elseif ~isfinite(picoTarea) || picoTarea <= 1e-9
        warning('%s: canal SIN SEÑAL en las tareas (RMS = 0 o vacío). Queda en NaN.',nombreMusculo(m));
        mvc.(m) = NaN; mvcOrigen.(m) = "SIN SEÑAL (canal muerto)";
    elseif ~isfinite(mvc.(m)) || mvc.(m) < fracMinMVCvsTarea*picoTarea
        if ocultarMusculosSinMVC
            warning('%s: sin MVC válido; el músculo se EXCLUYE (no es posible dar %%MVC real).',nombreMusculo(m));
            mvc.(m) = NaN; mvcOrigen.(m) = "SIN MVC VÁLIDO (excluido)";
        else
            warning(['%s: MVC (%.4g) incompatible con la escala de la tarea (pico %.4g). ' ...
                     'Se normaliza al PICO DE LA TAREA: NO es %%MVC real.'],nombreMusculo(m),mvc.(m),picoTarea);
            mvc.(m) = picoTarea; mvcOrigen.(m) = "PICO TAREA (MVC inválido)";
        end
    end
end

tablaMVC = table(string(musculos(:)),cellfun(@(m) string(nombreMusculo(m)),musculos(:)), ...
    cellfun(@(m) mvc.(m),musculos(:)),cellfun(@(m) mvcOrigen.(m),musculos(:)), ...
    cellfun(@(m) mvcInfo.(m).nValidos,musculos(:)),cellfun(@(m) mvcInfo.(m).ratio,musculos(:)), ...
    'VariableNames',{'Codigo','Musculo','MVC_RMS_uV','Origen','N_ensayos_validos','Ratio_max_min'});
disp(tablaMVC); writetable(tablaMVC,[paciente '_valores_MVC.csv']);

for is = 1:numel(SIG)
    s = SIG{is};
    for j = 1:numel(musculos)
        m = musculos{j}; s.(m) = 100*s.rms.(m)/mvc.(m);
        if isfinite(limiteArtefactoEMG_pct)
            nrem = nnz(s.(m) > limiteArtefactoEMG_pct);
            if nrem > 0
                fprintf('  %s %s: %d muestras (%.1f %%) > %g %%MVC descartadas como artefacto\n', ...
                    s.archivo,m,nrem,100*nrem/numel(s.(m)),limiteArtefactoEMG_pct);
                nArtefacto.(m) = nArtefacto.(m) + nrem;
                s.(m)(s.(m) > limiteArtefactoEMG_pct) = NaN;
            end
        end
    end
    t = s.t;
    Tout = table(t,s.hipFlexD,s.hipFlexI,s.kneeFlexD,s.kneeFlexI,s.GM_D,s.GM_I,s.VM_D,s.VL_D, ...
        s.VM_I,s.VL_I,s.BF_D,s.BF_I,'VariableNames',{'Tiempo_s','Cadera_Flex_D','Cadera_Flex_I', ...
        'Rodilla_Flex_D','Rodilla_Flex_I','GM_D_pctMVC','GM_I_pctMVC','VM_D_pctMVC','VL_D_pctMVC', ...
        'VM_I_pctMVC','VL_I_pctMVC','BF_D_pctMVC','BF_I_pctMVC'});
    writetable(Tout,[s.base '_' paciente '_senales_procesadas.csv']);
    SIG{is} = s;

    if figurasPorArchivo
        f = nuevaFigura(['Diagnóstico - ' s.archivo],[100 50 1000 800]);
        tiledlayout(f,2,1,'TileSpacing','compact');
        nexttile; hold on; h1 = plot(t,s.hipFlexD,'LineWidth',1.2); h2 = plot(t,s.hipFlexI,'LineWidth',1.2);
        grid on; ylabel('Grados'); title('Cadera flex-ext');
        legend([h1 h2],{'Derecha','Izquierda'},'Location','northeast');
        nexttile; hold on; h1 = plot(t,s.kneeFlexD,'LineWidth',1.2); h2 = plot(t,s.kneeFlexI,'LineWidth',1.2);
        grid on; ylabel('Grados'); xlabel('Tiempo (s)'); title('Rodilla flex-ext');
        legend([h1 h2],{'Derecha','Izquierda'},'Location','northeast');
        sgtitle(s.archivo);
        guardarYMostrar(f,fullfile(carpetaFiguras,[s.base '_diagnostico.png']),mostrarFigurasEnPantalla);
    end
end

%% ============================================================
% 8. FASE 2: SEGMENTAR REPETICIONES Y NORMALIZAR EN TIEMPO
% =============================================================
ACUM = struct(); filas = [];
for is = 1:numel(SIG)
    s = SIG{is}; ej = s.ejercicio;
    if isKey(modoSegmentacion,ej), modoOrig = modoSegmentacion(ej); else, modoOrig = 'ambas'; end
    modo = modoOrig;
    fDs = mean(isfinite(s.kneeFlexD(s.iStart:s.iEnd))); fIs = mean(isfinite(s.kneeFlexI(s.iStart:s.iEnd)));
    switch modoOrig
        case 'D'
            if fDs < 0.5 && fIs >= 0.5, xSeg = s.kneeFlexI; modo = 'I (sustituye a D)'; else, xSeg = s.kneeFlexD; end
        case 'I'
            if fIs < 0.5 && fDs >= 0.5, xSeg = s.kneeFlexD; modo = 'D (sustituye a I)'; else, xSeg = s.kneeFlexI; end
        case 'HD', xSeg = s.hipFlexD;
        case 'HI', xSeg = s.hipFlexI;
        case 'VLD', xSeg = s.VL_D;
        case 'VLI', xSeg = s.VL_I;
        otherwise
            if min(fDs,fIs) >= 0.8, xSeg = mean([s.kneeFlexD s.kneeFlexI],2,'omitnan');
            elseif fDs >= fIs, xSeg = s.kneeFlexD; modo = 'D (automático)';
            else, xSeg = s.kneeFlexI; modo = 'I (automático)'; end
    end
    centrado = any(strcmp(modoOrig,{'VLD','VLI'}));
    if centrado, promUse = promMinVL_pct; fracUse = fracPromVL;
    else
        promUse = prominenciaMin_deg;
        if isKey(fraccionProminenciaEj,ej), fracUse = fraccionProminenciaEj(ej); else, fracUse = fraccionProminencia; end
    end
    if isKey(distanciaMinPicosEj,ej), dmin = distanciaMinPicosEj(ej); else, dmin = distanciaMinPicos_s; end
    if isKey(padFinalSeg_s,ej), padS = round(padFinalSeg_s(ej)*s.Fs); else, padS = 0; end
    iEndSeg = min(numel(s.t),s.iEnd + padS);
    reps = segmentarRepeticiones(xSeg,s.iStart,iEndSeg,s.Fs,dmin,promUse, ...
        fracUse,incluirRepIncompleta,centrado,tolCentrado);
    if ~isempty(reps)
        keep = false(size(reps,1),1);
        for k = 1:size(reps,1), keep(k) = mean(isfinite(xSeg(reps(k,1):reps(k,2)))) >= 0.9; end
        if any(~keep), fprintf('  %s: %d repetición(es) descartada(s) por huecos en la señal de segmentación\n',s.archivo,nnz(~keep)); end
        reps = reps(keep,:);
    end
    msgFrag = '';
    if size(reps,1) >= 2
        durR = (s.t(reps(:,2)) - s.t(reps(:,1)));
        frag = durR < fracDurMinRep*median(durR);
        if any(frag)
            msgFrag = sprintf('   DESCARTADAS %d repeticion(es) < %.0f %% de la mediana (%.2f s): %s s\n',nnz(frag), ...
                100*fracDurMinRep,median(durR),mat2str(round(durR(frag)',2)));
            reps(frag,:) = [];
        end
    end
    if centrado, txtCentr = ', centrada en el pico'; else, txtCentr = ''; end
    fprintf('%s (%s, segmentación "%s"%s): %d repeticiones válidas\n',s.archivo,nombreDe(nombreEjercicio,ej),modo, ...
        txtCentr,size(reps,1));
    if ~isempty(msgFrag), fprintf('%s',msgFrag); end
    if isKey(excluirVentana,s.archivo) && ~isempty(reps)
        wEx = excluirVentana(s.archivo);
        tm = (s.t(reps(:,1)) + s.t(reps(:,2)))/2;
        malas = tm >= wEx(1) & tm <= wEx(2);
        fprintf('   EXCLUIDAS %d repeticion(es) de %s en la ventana %.1f-%.1f s\n',nnz(malas),s.archivo,wEx(1),wEx(2));
        reps(malas,:) = [];
    end
    for rr = 1:size(reps,1)
        fprintf('   rep %d: %6.2f - %6.2f s (%.2f s)\n',rr,s.t(reps(rr,1)),s.t(reps(rr,2)), ...
            s.t(reps(rr,2))-s.t(reps(rr,1)));
    end
    SIG{is}.reps = reps;

    for r = 1:size(reps,1)
        ia = reps(r,1); ib = reps(r,2);
        tr = s.t(ia:ib); tn = linspace(tr(1),tr(end),nPuntos);
        for v = 1:numel(vars)
            yv = s.(vars{v})(ia:ib);
            if mean(~isfinite(yv)) > 0.05, yv(:) = NaN; end
            % v3.2: excluirROM tambien anula la articulacion en las curvas medias
            if isKey(mapaVarROM,vars{v}) && isKey(excluirROM,s.archivo) && ...
                    any(strcmp(excluirROM(s.archivo),mapaVarROM(vars{v})))
                yv(:) = NaN;
            end
            yn = interp1(tr,yv,tn,'linear');
            if ~isfield(ACUM,ej) || ~isfield(ACUM.(ej),vars{v}), ACUM.(ej).(vars{v}) = yn;
            else, ACUM.(ej).(vars{v}) = [ACUM.(ej).(vars{v}); yn]; end
        end
        f = struct();
        f.Ejercicio = string(ej); f.Archivo = string(s.archivo); f.Rep = r; f.Duracion_s = tr(end)-tr(1);
        f.ROM_Cadera_D  = romValido(s.hipFlexD(ia:ib));
        f.ROM_Cadera_I  = romValido(s.hipFlexI(ia:ib));
        f.ROM_Rodilla_D = romValido(s.kneeFlexD(ia:ib));
        f.ROM_Rodilla_I = romValido(s.kneeFlexI(ia:ib));
        if isKey(excluirROM,s.archivo)
            exj = excluirROM(s.archivo);
            if any(strcmp(exj,'hipD')),  f.ROM_Cadera_D  = NaN; end
            if any(strcmp(exj,'hipI')),  f.ROM_Cadera_I  = NaN; end
            if any(strcmp(exj,'kneeD')), f.ROM_Rodilla_D = NaN; end
            if any(strcmp(exj,'kneeI')), f.ROM_Rodilla_I = NaN; end
        end
        for j = 1:numel(musculos)
            m = musculos{j}; y = s.(m)(ia:ib);
            if mean(~isfinite(y)) > 0.05, y(:) = NaN; end
            f.(['Media_' m '_pctMVC'])      = mean(y,'omitnan');
            f.(['Pico_' m '_pctMVC'])       = max(y,[],'omitnan');
            if all(isnan(y)), f.(['Integral_' m '_pctMVC_s']) = NaN;
            else, f.(['Integral_' m '_pctMVC_s']) = trapz(tr,fillmissing(y,'constant',0)); end
        end
        filas = [filas; f]; %#ok<AGROW>
    end
end
if isempty(filas), error('No se detectó ninguna repetición.'); end

T = struct2table(filas);
T.NombreEjercicio = arrayfun(@(e) string(nombreDe(nombreEjercicio,char(e))),T.Ejercicio);
writetable(T,[paciente '_metricas_por_repeticion.csv']);
ejs = fieldnames(ACUM);
nomEj = cellfun(@(e) nombreDe(nombreEjercicio,e),ejs,'UniformOutput',false);

%% ============================================================
% 9. TABLAS: EMG, ROM, SIMETRIA, CALIDAD
% =============================================================
filasEMG = [];
for ie = 1:numel(ejs)
    sel = T.Ejercicio == string(ejs{ie});
    for j = 1:numel(musculos)
        m = musculos{j};
        media = T.(['Media_' m '_pctMVC'])(sel); pico = T.(['Pico_' m '_pctMVC'])(sel);
        integ = T.(['Integral_' m '_pctMVC_s'])(sel);
        g = struct();
        g.Ejercicio = string(nomEj{ie}); g.Musculo = string(nombreMusculo(m));
        g.MVC_RMS = mvc.(m); g.Origen_MVC = mvcOrigen.(m); g.N_repeticiones = nnz(sel); g.N_validas = nnz(isfinite(pico));
        g.Media_pctMVC = mean(media,'omitnan'); g.SD_Media_pctMVC = std(media,'omitnan');
        g.Pico_pctMVC = mean(pico,'omitnan');   g.SD_Pico_pctMVC = std(pico,'omitnan');
        g.Integral_pctMVC_s = mean(integ,'omitnan');
        filasEMG = [filasEMG; g]; %#ok<AGROW>
    end
end
tablaEMG = struct2table(filasEMG);
writetable(tablaEMG,[paciente '_resultados_EMG_pctMVC.csv']);
disp('RESULTADOS EMG (%MVC) POR EJERCICIO Y MÚSCULO:'); disp(tablaEMG);

filasROM = [];
for ie = 1:numel(ejs)
    sel = T.Ejercicio == string(ejs{ie});
    g = struct(); g.Ejercicio = string(nomEj{ie}); g.N_repeticiones = nnz(sel);
    g.Duracion_rep_s = mean(T.Duracion_s(sel),'omitnan');
    for art = {'Cadera','Rodilla'}
        for lado = {'D','I'}
            v = T.(['ROM_' art{1} '_' lado{1}])(sel);
            g.(['ROM_' art{1} '_' lado{1} '_media_deg']) = mean(v,'omitnan');
            g.(['ROM_' art{1} '_' lado{1} '_SD_deg'])    = std(v,'omitnan');
            g.(['N_' art{1} '_' lado{1}])                = nnz(isfinite(v));
        end
    end
    filasROM = [filasROM; g]; %#ok<AGROW>
end
tablaROM = struct2table(filasROM);
writetable(tablaROM,[paciente '_resultados_ROM.csv']);
disp('RANGO DE MOVIMIENTO (flex-ext) POR EJERCICIO:'); disp(tablaROM);

filasSim = [];
for ie = 1:numel(ejs)
    sel = T.Ejercicio == string(ejs{ie});
    for ib = 1:numel(paresBase)
        b = paresBase{ib};
        for tipo = {'Pico','Media'}
            d = mean(T.([tipo{1} '_' b '_D_pctMVC'])(sel),'omitnan');
            iz = mean(T.([tipo{1} '_' b '_I_pctMVC'])(sel),'omitnan');
            g = struct(); g.Ejercicio = string(nomEj{ie});
            g.Variable = string([tipo{1} ' %MVC - ' nombreBase{ib}]);
            g.Derecha = d; g.Izquierda = iz; g.IndiceSimetria_pct = 100*(d-iz)/((d+iz)/2);
            filasSim = [filasSim; g]; %#ok<AGROW>
        end
    end
    for art = {'Cadera','Rodilla'}
        d = mean(T.(['ROM_' art{1} '_D'])(sel),'omitnan'); iz = mean(T.(['ROM_' art{1} '_I'])(sel),'omitnan');
        g = struct(); g.Ejercicio = string(nomEj{ie}); g.Variable = string(['ROM ' art{1} ' (grados)']);
        g.Derecha = d; g.Izquierda = iz; g.IndiceSimetria_pct = 100*(d-iz)/((d+iz)/2);
        filasSim = [filasSim; g]; %#ok<AGROW>
    end
end
tablaSim = struct2table(filasSim);
writetable(tablaSim,[paciente '_comparacion_lados.csv']);
disp('COMPARACIÓN DERECHA vs IZQUIERDA:'); disp(tablaSim);

archivosSIG = cellfun(@(q) q.archivo,SIG,'UniformOutput',false);
nM = numel(musculos);
picoMax = zeros(nM,1); nSobre100 = zeros(nM,1); aviso = strings(nM,1);
for j = 1:nM
    m = musculos{j};
    p = T.(['Pico_' m '_pctMVC']);
    picoMax(j) = max(p,[],'omitnan'); nSobre100(j) = nnz(p > 100);
    pf = cellfun(@(q) prctile(q.(m),99),SIG);
    apag = pf < 2;
    if startsWith(mvcOrigen.(m),"SIN SEÑAL")
        aviso(j) = "Canal SIN SEÑAL (RMS = 0 o vacío): excluir este músculo del análisis";
    elseif startsWith(mvcOrigen.(m),"SIN MVC")
        aviso(j) = "Sin MVC válido: excluido (no se puede dar %MVC real)";
    elseif mvcOrigen.(m) == "PICO TAREA (MVC inválido)"
        aviso(j) = "MVC inválido: valores relativos al pico de la tarea, NO %MVC real. Repetir/revisar MVC";
    elseif any(apag) && any(pf > 20)
        aviso(j) = "Canal casi plano SOLO en: " + string(strjoin(archivosSIG(apag),', ')) + " (¿electrodo desconectado?)";
    elseif picoMax(j) < 5,   aviso(j) = "Casi plano: revisar canal";
    elseif picoMax(j) < 15,  aviso(j) = "Pico < 15 %MVC en todas las tareas: MVC posiblemente inflado (artefacto) o poca señal";
    elseif picoMax(j) > 120, aviso(j) = "Supera su MVC: posible MVC infravalorado o artefactos";
    else, aviso(j) = "OK"; end
end
tablaQC = table(cellfun(@(m) string(nombreMusculo(m)),musculos(:)),cellfun(@(m) mvc.(m),musculos(:)), ...
    cellfun(@(m) mvcOrigen.(m),musculos(:)),picoMax,nSobre100,aviso, ...
    'VariableNames',{'Musculo','MVC_RMS_uV','Origen_MVC','PicoMax_pctMVC','Reps_pico_mayor_100','Aviso'});
writetable(tablaQC,[paciente '_control_calidad_EMG.csv']);
disp('CONTROL DE CALIDAD EMG:'); disp(tablaQC);

% Calidad cinematica por archivo
filasCin = [];
for is = 1:numel(SIG)
    s = SIG{is}; g = struct(); g.Archivo = string(s.archivo);
    g.pctInv_PelvisD = s.pctInvSensor(1); g.pctInv_MusloD = s.pctInvSensor(2); g.pctInv_TibiaD = s.pctInvSensor(3);
    g.pctInv_PelvisI = s.pctInvSensor(4); g.pctInv_MusloI = s.pctInvSensor(5); g.pctInv_TibiaI = s.pctInvSensor(6);
    g.pctValido_CaderaD = s.pctValido(1); g.pctValido_CaderaI = s.pctValido(2);
    g.pctValido_RodillaD = s.pctValido(3); g.pctValido_RodillaI = s.pctValido(4);
    g.Lag_I_vs_D_s = s.lagIzq; g.Lag_bruto_s = s.lagBruto; g.Lag_EMG_orientativo_s = s.lagEMG;
    wD = ventanaT(s.t,s.restD); wI = ventanaT(s.t,s.restI);
    g.Reposo_D_inicio_s = wD(1); g.Reposo_I_inicio_s = wI(1);
    filasCin = [filasCin; g]; %#ok<AGROW>
end
writetable(struct2table(filasCin),[paciente '_calidad_cinematica_por_archivo.csv']);

%% ============================================================
% 10A. MOVIMIENTO REAL POR EJERCICIO (4 filas x n series)  [version ligera]
% =============================================================
if figurasMovimientoReal
    for ie = 1:numel(ejs)
        idxSer = find(cellfun(@(q) strcmp(q.ejercicio,ejs{ie}),SIG));
        nS = numel(idxSer);
        figR = nuevaFigura(['Movimiento real - ' nomEj{ie}],[50 50 min(1800,560*nS) 1050]);
        tl = tiledlayout(figR,4,nS,'TileSpacing','compact');
        axR = gobjects(4,nS);
        for r = 1:4
            for k = 1:nS
                q = SIG{idxSer(k)};
                ax = nexttile(tl); axR(r,k) = ax; hold(ax,'on');
                d = max(1,round(q.Fs/200)); ii = 1:d:numel(q.t); tt = q.t(ii);
                switch r
                    case 1
                        h = [plot(ax,tt,q.hipFlexD(ii),'LineWidth',1.2) plot(ax,tt,q.hipFlexI(ii),'LineWidth',1.2)];
                        etq = {'Derecha','Izquierda'}; ylab = 'Grados';
                        if ~any(isfinite(q.kneeFlexI)), txtLag = 'I sin IMU';
                        else, txtLag = sprintf('lag I = %+.2f s%s',q.lagBruto,ifelse(q.alineado,', alineada','')); end
                        title(ax,sprintf('%s - Cadera flex-ext (%s)',q.archivo,txtLag));
                    case 2
                        h = [plot(ax,tt,q.kneeFlexD(ii),'LineWidth',1.2) plot(ax,tt,q.kneeFlexI(ii),'LineWidth',1.2)];
                        etq = {'Derecha','Izquierda'}; ylab = 'Grados'; title(ax,'Rodilla flex-ext');
                    case 3
                        h = [plot(ax,tt,q.VM_D(ii)) plot(ax,tt,q.VL_D(ii)) plot(ax,tt,q.VM_I(ii)) plot(ax,tt,q.VL_I(ii))];
                        etq = {'VM D','VL D','VM I','VL I'}; ylab = '%MVC'; title(ax,'Cuádriceps (%MVC)');
                    case 4
                        h = [plot(ax,tt,q.GM_D(ii)) plot(ax,tt,q.GM_I(ii)) plot(ax,tt,q.BF_D(ii)) plot(ax,tt,q.BF_I(ii))];
                        etq = {'GM D','GM I','Isquio D','Isquio I'}; ylab = '%MVC';
                        title(ax,'Glúteo medio e isquiotibiales (%MVC)'); xlabel(ax,'Tiempo (s)');
                end
                grid(ax,'on');
                if k == 1, ylabel(ax,ylab); legend(ax,h,etq,'Location','northeast'); end
            end
        end
        tIni = min(cellfun(@(q) q.t(1),SIG(idxSer))); tFin = max(cellfun(@(q) q.t(end),SIG(idxSer)));
        set(axR(:),'XLim',[tIni tFin]);
        for r = 1:4
            yl = [inf -inf];
            for k = 1:nS, l = ylim(axR(r,k)); yl = [min(yl(1),l(1)) max(yl(2),l(2))]; end
            if ~all(isfinite(yl)) || yl(1) >= yl(2), yl = [0 1]; end
            set(axR(r,:),'YLim',yl);
        end
        for r = 1:4
            for k = 1:nS, decorarMovimiento(axR(r,k),SIG{idxSer(k)}); end
        end
        sgtitle(tl,sprintf('%s - %s - movimiento real de cada serie',paciente,nomEj{ie}));
        archivoPNG = fullfile(carpetaFiguras,[paciente '_movimiento_real_' ejs{ie} '.png']);
        guardarYMostrar(figR,archivoPNG,mostrarFigurasEnPantalla);
        fprintf('Movimiento real: %s -> %s\n',nomEj{ie},archivoPNG);
    end
end

%% ============================================================
% 10B. MOVIMIENTO MEDIO POR EJERCICIO
% =============================================================
x = linspace(0,100,nPuntos);
if figurasMediaPorEjercicio
    for ie = 1:numel(ejs)
        A = ACUM.(ejs{ie}); nR = size(A.kneeFlexD,1); c = lines(4);
        nvD = nnz(any(isfinite(A.hipFlexD),2)); nvI = nnz(any(isfinite(A.hipFlexI),2));
        figMov = nuevaFigura(['Movimiento medio - ' nomEj{ie}],[100 50 850 1000]);
        tl = tiledlayout(figMov,4,1,'TileSpacing','compact');
        nexttile(tl); hold on;
        plotBanda(x,A.hipFlexD,c(1,:),'Derecha',true); plotBanda(x,A.hipFlexI,c(2,:),'Izquierda',true);
        grid on; xlim([0 100]); ylabel('Grados'); legend('Location','best');
        title(sprintf('Cadera - flex-ext (n = %d repeticiones; válidas: D = %d, I = %d; grueso = media ± DE, fino = cada repetición)',nR,nvD,nvI));
        nexttile(tl); hold on;
        plotBanda(x,A.kneeFlexD,c(1,:),'Derecha',true); plotBanda(x,A.kneeFlexI,c(2,:),'Izquierda',true);
        grid on; xlim([0 100]); ylabel('Grados'); legend('Location','best'); title('Rodilla - flex-ext');
        nexttile(tl); hold on;
        plotBanda(x,A.VM_D,c(1,:),nombreMusculo('VM_D')); plotBanda(x,A.VL_D,c(2,:),nombreMusculo('VL_D'));
        plotBanda(x,A.VM_I,c(3,:),nombreMusculo('VM_I')); plotBanda(x,A.VL_I,c(4,:),nombreMusculo('VL_I'));
        grid on; xlim([0 100]); ylabel('%MVC'); legend('Location','best'); title('Cuádriceps');
        nexttile(tl); hold on;
        plotBanda(x,A.GM_D,c(1,:),nombreMusculo('GM_D')); plotBanda(x,A.GM_I,c(2,:),nombreMusculo('GM_I'));
        plotBanda(x,A.BF_D,c(3,:),'Isquiotibiales D'); plotBanda(x,A.BF_I,c(4,:),'Isquiotibiales I');
        grid on; xlim([0 100]); xlabel('% del ciclo de repetición'); ylabel('%MVC');
        legend('Location','best'); title('Glúteo medio e isquiotibiales');
        sgtitle(tl,sprintf('%s - %s - movimiento medio de todas las series',paciente,nomEj{ie}));
        archivoPNG = fullfile(carpetaFiguras,[paciente '_movimiento_medio_' ejs{ie} '.png']);
        guardarYMostrar(figMov,archivoPNG,mostrarFigurasEnPantalla);
        fprintf('Movimiento medio: %s -> %s\n',nomEj{ie},archivoPNG);

        M = x(:); nomCol = {'Ciclo_pct'};
        for v = 1:numel(vars)
            M(:,end+1) = mean(A.(vars{v}),1,'omitnan')';  nomCol{end+1} = ['Media_' vars{v}]; %#ok<SAGROW>
            M(:,end+1) = std(A.(vars{v}),0,1,'omitnan')'; nomCol{end+1} = ['SD_' vars{v}];    %#ok<SAGROW>
        end
        writetable(array2table(M,'VariableNames',nomCol),[paciente '_curvas_medias_' ejs{ie} '.csv']);
    end
end

%% ============================================================
% 11. COMPARACION ENTRE EJERCICIOS
% =============================================================
if figurasComparacion
    nombresMusLargos = cellfun(@(m) nombreMusculo(m),musculos,'UniformOutput',false);
    f1 = nuevaFigura('EMG en %MVC por ejercicio',[100 50 1000 800]);
    tl = tiledlayout(f1,2,1,'TileSpacing','compact');
    nexttile(tl); graficoBarrasEMG(T,ejs,nomEj,musculos,nombresMusLargos,'Pico_','Pico (%MVC)', ...
        'Pico de activación por músculo (media ± DE entre repeticiones)');
    nexttile(tl); graficoBarrasEMG(T,ejs,nomEj,musculos,nombresMusLargos,'Media_','Media (%MVC)', ...
        'Activación media por músculo (media ± DE entre repeticiones)');
    sgtitle(tl,sprintf('%s - EMG normalizado respecto al MVC',paciente));
    guardarYMostrar(f1,fullfile(carpetaFiguras,[paciente '_comparacion_EMG.png']),mostrarFigurasEnPantalla);

    f2 = nuevaFigura('Rango de movimiento por ejercicio',[100 50 900 450]);
    tl = tiledlayout(f2,1,2,'TileSpacing','compact');
    nexttile(tl); graficoBarrasLado(T,ejs,nomEj,'ROM_Cadera_D','ROM_Cadera_I','Grados','Cadera (flex-ext)');
    nexttile(tl); graficoBarrasLado(T,ejs,nomEj,'ROM_Rodilla_D','ROM_Rodilla_I','Grados','Rodilla (flex-ext)');
    sgtitle(tl,sprintf('%s - Rango de movimiento por ejercicio',paciente));
    guardarYMostrar(f2,fullfile(carpetaFiguras,[paciente '_comparacion_ROM.png']),mostrarFigurasEnPantalla);
end

%% ============================================================
% 12. RESUMEN PARA LA COMPARACION GLOBAL (pierna operada vs sana)
% =============================================================
% LSI = operada / sana x 100, con las medias de cada variable.
% Sentarse-levantarse: ambas piernas en la misma tarea.
% Subida de escalon: operada en la serie en que ELLA inicia; sana en la serie en que ELLA inicia.
% Canal sin senal en UN lado (o sin MVC valido) -> Calidad 0 y LSI NaN.
% Sin datos validos en operada o sana (p. ej. ROM de P5 en el lado I) -> Calidad 0 y LSI NaN.
ladoSan = setdiff('DI',ladoOperado);
exOp = ['E' ladoOperado]; exSan = ['E' ladoSan];
defs = {};
for b = {'VM','VL','GM','BF'}
    defs(end+1,:) = {['Pico_'  b{1}], ['Pico_'  b{1} '_%s_pctMVC'], b{1}, 'EMG'}; %#ok<SAGROW>
    defs(end+1,:) = {['Media_' b{1}], ['Media_' b{1} '_%s_pctMVC'], b{1}, 'EMG'}; %#ok<SAGROW>
end
defs(end+1,:) = {'ROM_Cadera', 'ROM_Cadera_%s', 'hip',  'ROM'};
defs(end+1,:) = {'ROM_Rodilla','ROM_Rodilla_%s','knee', 'ROM'};

filasG = [];
for k = 1:size(defs,1)
    for tk = 1:2
        if tk == 1, ejO = 'S'; ejS = 'S'; tarea = "S"; else, ejO = exOp; ejS = exSan; tarea = "Step"; end
        selO = T.Ejercicio == string(ejO); selS = T.Ejercicio == string(ejS);
        vo = T.(sprintf(defs{k,2},ladoOperado))(selO);
        vs = T.(sprintf(defs{k,2},ladoSan))(selS);
        mo = mean(vo,'omitnan'); ms = mean(vs,'omitnan');

        cal = 2; motivo = strings(0,1); sinSenal = false;
        if strcmp(defs{k,4},'EMG')
            for L = [ladoOperado ladoSan]
                m = [defs{k,3} '_' L];
                if nArtefacto.(m) > 0
                    cal = min(cal,1); motivo(end+1) = "artefactos EMG descartados " + string(L); %#ok<SAGROW>
                end
                if startsWith(mvcOrigen.(m),"SIN")
                    cal = 0; sinSenal = true; motivo(end+1) = "canal sin señal / sin MVC válido " + string(L); %#ok<SAGROW>
                elseif mvcOrigen.(m) == "PICO TAREA (MVC inválido)"
                    cal = 0; motivo(end+1) = "MVC inválido " + string(L); %#ok<SAGROW>
                else
                    if mvcInfo.(m).nValidos == 1
                        cal = min(cal,1); motivo(end+1) = "MVC de un ensayo " + string(L); %#ok<SAGROW>
                    end
                    if isfinite(mvcInfo.(m).ratio) && mvcInfo.(m).ratio > 3
                        cal = min(cal,1); motivo(end+1) = "MVC inconsistente " + string(L); %#ok<SAGROW>
                    end
                end
            end
            pkO = T.(['Pico_' defs{k,3} '_' ladoOperado '_pctMVC'])(selO);
            pkS = T.(['Pico_' defs{k,3} '_' ladoSan '_pctMVC'])(selS);
            for iL = 1:2
                if iL == 1, pkL = pkO; Ls = ladoOperado; else, pkL = pkS; Ls = ladoSan; end
                if isempty(pkL) || all(~isfinite(pkL)) || max(pkL,[],'omitnan') < umbralCanalPlano_pct
                    cal = 0; sinSenal = true;
                    motivo(end+1) = sprintf("canal sin señal %s (pico < %g %%MVC)",Ls,umbralCanalPlano_pct); %#ok<SAGROW>
                end
            end
            pk = [pkO; pkS];
            fr100 = mean(pk > 100,'omitnan');
            if fr100 >= fracRepsSobre100
                cal = min(cal,1); motivo(end+1) = sprintf("%.0f %% de repeticiones con pico > 100 %% MVC",100*fr100); %#ok<SAGROW>
            end
            if max(pk,[],'omitnan') < 15
                cal = min(cal,1); motivo(end+1) = "activación < 15 %: MVC posiblemente inflado"; %#ok<SAGROW>
            end
        else
            for L = [ladoOperado ladoSan]
                ve = varExpl.([defs{k,3} L]);
                if ve < umbralNoInterpEje
                    cal = 0; motivo(end+1) = sprintf("eje %s %.0f %%",L,100*ve); %#ok<SAGROW>
                elseif ve < umbralEje
                    cal = min(cal,1); motivo(end+1) = sprintf("eje %s %.0f %%",L,100*ve); %#ok<SAGROW>
                end
                sel = tablaEjes.Articulacion == string([defs{k,3} L]) & tablaEjes.Archivo ~= "GLOBAL";
                kex = keys(excluirROM);
                for ke = 1:numel(kex)
                    if any(strcmp(excluirROM(kex{ke}),[defs{k,3} L])), sel = sel & tablaEjes.Archivo ~= string(kex{ke}); end
                end
                vmin = min(tablaEjes.VarExplicada(sel),[],'omitnan');
                if isfinite(vmin) && vmin < umbralNoInterpEje
                    if ejeArchivoAnulaCalidad, cal = 0; else, cal = min(cal,1); end
                    motivo(end+1) = sprintf("mín. por archivo %s %.0f %%",L,100*vmin); %#ok<SAGROW>
                end
                amb = any(tablaEjes.Articulacion == string([defs{k,3} L]) & tablaEjes.SignoAmbiguo);
                if amb, cal = min(cal,1); motivo(end+1) = "signo ambiguo " + string(L); end %#ok<SAGROW>
            end
            nOp = nnz(isfinite(vo)); nSa = nnz(isfinite(vs));
            if min(nOp,nSa) < nMinROM
                cal = 0; motivo(end+1) = sprintf("n efectivo %d (op) / %d (sana)",nOp,nSa); %#ok<SAGROW>
            end
        end
        clave = sprintf('%s|%s',defs{k,1},tarea);
        if isKey(calidadManual,clave), cal = calidadManual(clave); motivo(end+1) = "ajuste manual"; end %#ok<SAGROW>
        if ~(isfinite(mo) && isfinite(ms))
            cal = 0;
            if isempty(motivo), motivo(end+1) = "sin datos válidos (operada o sana)"; end %#ok<SAGROW>
        end
        if isempty(motivo), motivo = "OK"; end
        lsi = 100*mo/ms;
        if sinSenal || ~(isfinite(mo) && isfinite(ms)), lsi = NaN; end

        g = struct('Paciente',string(paciente),'LadoOperado',string(ladoOperado), ...
            'Variable',string(defs{k,1}),'Tarea',tarea, ...
            'Op_media',mo,'Op_SD',std(vo,'omitnan'),'Op_n',nnz(isfinite(vo)), ...
            'San_media',ms,'San_SD',std(vs,'omitnan'),'San_n',nnz(isfinite(vs)), ...
            'Delta',mo-ms,'LSI',lsi,'Calidad',cal,'Motivo',strjoin(motivo,"; "));
        filasG = [filasG; g]; %#ok<AGROW>
    end
end
tablaG = struct2table(filasG);
writetable(tablaG,[paciente '_resumen_global.csv']);
disp(tablaG(:,{'Variable','Tarea','Op_media','San_media','LSI','Calidad','Motivo'}));

fprintf('\nTerminado. Figuras en la carpeta "%s".\n',carpetaFiguras);
fprintf('Revisa %s_unidades_EMG_originales.csv, %s_ejes_articulares.csv, %s_calidad_cinematica_por_archivo.csv y el control de calidad EMG.\n', ...
    paciente,paciente,paciente);

%% ============================================================
% FUNCIONES LOCALES
% =============================================================
function v = ifelse(c,a,b)
    if c, v = a; else, v = b; end
end

function g = filaEje(archivo,art,ax,expl,cosG,amb,metodo,rho)
    g = struct(); g.Archivo = string(archivo); g.Articulacion = string(art);
    g.ex = ax(1); g.ey = ax(2); g.ez = ax(3); g.VarExplicada = expl;
    g.CosConGlobal = cosG; g.SignoAmbiguo = amb; g.Metodo = string(metodo); g.RhoCaderaRodilla = rho;
end

function decorarMovimiento(ax,q)
    yl = ylim(ax); xl = xlim(ax);
    plot(ax,xl,[0 0],':k','HandleVisibility','off');
    b = [q.t(q.iStart) q.t(q.iEnd)];
    plot(ax,reshape([b; b; NaN(1,numel(b))],1,[]),repmat([yl(1) yl(2) NaN],1,numel(b)), ...
        '--k','HandleVisibility','off');
    if ~isempty(q.reps)
        bb = q.t(unique(q.reps(:)))';
        plot(ax,reshape([bb; bb; NaN(1,numel(bb))],1,[]),repmat([yl(1) yl(2) NaN],1,numel(bb)), ...
            ':','Color',[0.6 0.6 0.6],'HandleVisibility','off');
    end
end

function [i1,i2] = intervaloActivo(kD,kI,Fs,umbral,gap_s,minDur_s)
    active = abs(kD) > umbral | abs(kI) > umbral;   % NaN -> false
    active = rellenarHuecos(active,round(gap_s*Fs));
    active = quitarTramosCortos(active,round(minDur_s*Fs));
    if any(active), ii = find(active); i1 = ii(1); i2 = ii(end);
    else, i1 = 1; i2 = numel(kD); end
end

function [a,nSaltos,idxSaltos] = limpiarSaltos(a,Fs,vmax)
    a = a(:); nSaltos = 0; idxSaltos = [];
    d = [0; diff(a)]*Fs; d(~isfinite(d)) = 0;
    cand = find(abs(d) > vmax);
    if isempty(cand), return; end
    w = round(0.15*Fs); m = round(0.3*Fs); N = numel(a);
    corte = [0; find(diff(cand) > m); numel(cand)];
    for g = 1:numel(corte)-1
        j1 = cand(corte(g)+1); j2 = cand(corte(g+1));
        i0 = max(1,j1-w); i3 = min(N,j2+w);
        dA = median(a(max(1,i0-m):i0),'omitnan');
        dB = median(a(i3:min(N,i3+m)),'omitnan');
        nSaltos = nSaltos + 1; idxSaltos(end+1) = j1; %#ok<AGROW>
        if isfinite(dA) && isfinite(dB) && abs(dB-dA) <= 20
            a(i0:i3) = NaN;
        else
            fin = find(isnan(a(i3:end)),1,'first');
            if isempty(fin), a(i0:end) = NaN; else, a(i0:i3+fin-2) = NaN; end
        end
    end
end

function r = romValido(x)
    if mean(~isfinite(x)) > 0.05, r = NaN; else, r = rangoSeguro(x); end
end

function w = ventanaT(t,rest)
    if any(rest), w = [t(find(rest,1,'first')) t(find(rest,1,'last'))]; else, w = [NaN NaN]; end
end

function f = nuevaFigura(nombre,pos)
    vis = getappdata(0,'visFig'); if isempty(vis), vis = 'off'; end
    f = figure('Name',nombre,'Color','w','Position',pos,'Visible',vis);
    try, theme(f,'light'); catch, end %#ok<NOCOM>
end

function guardarYMostrar(f,archivo,mostrar)
    drawnow; pause(0.2);
    try, exportgraphics(f,archivo,'Resolution',150,'BackgroundColor','white'); catch, end
    if ~imagenConContenido(archivo)
        warning('%s salió en blanco; se reintenta con print.',archivo);
        try, print(f,archivo,'-dpng','-r150'); catch, end
        if ~imagenConContenido(archivo)
            warning('%s sigue en blanco. Prueba con crearFigurasVisibles = true.',archivo);
        end
    end
    if mostrar, f.Visible = 'on'; else, close(f); end
end

function ok = imagenConContenido(archivo)
    ok = false;
    if ~isfile(archivo), return; end
    try, I = imread(archivo); ok = any(I(:) < 245); catch, end
end

function n = nombreDe(mapa,clave)
    if isKey(mapa,clave), n = mapa(clave); else, n = clave; end
end

function [x,unidad] = armonizarUnidadEMG(x)
    % OT BioLab exporta cada canal de cada archivo en uV o en mV. Se distingue por la
    % resolucion del ADC: 0,298 -> uV ; 0,000298 -> mV. Devuelve la senal siempre en uV.
    unidad = "uV";
    u = unique(x(isfinite(x) & x ~= 0));
    if numel(u) < 20, unidad = "sin datos"; return; end
    d = diff(u); d = d(d > 1e-9);
    if isempty(d), unidad = "sin datos"; return; end
    if min(d) < 0.01
        x = x*1000; unidad = "mV (x1000)";
    end
end

function q = limpiarQ(q,Fs,maxHueco_s)
    % Validez por norma RELATIVA (los nodos exportan con norma 8,19 o 8192).
    % Un nodo vacio (NaN o ceros) devuelve todo NaN.
    q = double(q);
    nm = sqrt(sum(q.^2,2));
    ref = median(nm(isfinite(nm) & nm > 0));
    if isempty(ref) || ~isfinite(ref), q(:) = NaN; return; end
    bad = any(~isfinite(q),2) | nm < 0.5*ref;
    q(bad,:) = NaN;
    last = find(~bad,1);
    if isempty(last), return; end
    for k = last+1:size(q,1)
        if bad(k), continue; end
        if dot(q(k,:),q(last,:)) < 0, q(k,:) = -q(k,:); end
        last = k;
    end
    q = fillmissing(q,'linear','MaxGap',round(maxHueco_s*Fs),'EndValues','none');
    n = sqrt(sum(q.^2,2)); q = q./n;
end

function rest = detectarReposo(Qs,Fs,win_s,search_s)
    N = size(Qs{1},1); sp = zeros(N,1); valid = true(N,1);
    for k = 1:numel(Qs)
        q = Qs{k}; valid = valid & all(isfinite(q),2);
        d = min(abs(sum(q(1:end-1,:).*q(2:end,:),2)),1);
        sp(2:end) = sp(2:end) + 2*acosd(d)*Fs;
    end
    rest = false(N,1);
    if ~any(valid), return; end       % lado sin senal (p. ej. muslo I de P5)
    sp(~valid | ~isfinite(sp)) = 1e6;
    w = max(10,round(win_s*Fs));
    m = movmean(sp,w); vf = movmean(double(valid),w);
    lo = ceil(w/2)+1; hi = min(N-ceil(w/2)-1,round(search_s*Fs));
    cand = lo:hi; cand = cand(vf(cand) > 0.99);
    if isempty(cand)
        warning('No se encontró ventana de reposo válida; se usan las primeras muestras válidas.');
        iv = find(valid,w); rest(iv) = true; return;
    end
    [~,k] = min(m(cand)); i0 = cand(k);
    rest(max(1,i0-floor(w/2)):min(N,i0+floor(w/2))) = true;
end

function r = corrDI(a,b)
    a = a(:); b = b(:);
    ok = isfinite(a) & isfinite(b);
    if nnz(ok) < 100 || std(a(ok)) == 0 || std(b(ok)) == 0, r = NaN; return; end
    c = corrcoef(a(ok),b(ok)); r = c(1,2);
end

function lag = lagIzqVsDer(kD,kI,Fs,maxLag_s)
    kD = kD(:); kI = kI(:);
    a0 = fillmissing(kD,'constant',0); b0 = fillmissing(kI,'constant',0);
    idx = find(abs(a0) > 0.3*max(abs(a0)));
    if numel(idx) < 10, lag = 0; return; end
    i1 = idx(1); i2 = idx(end);
    minDist = round(0.8*Fs);

    tR = picosGrandes(a0(i1:i2),minDist) + i1 - 1;
    j1 = max(1,i1 - round(maxLag_s*Fs));
    tL = picosGrandes(b0(j1:end),minDist) + j1 - 1;
    n = min(numel(tR),numel(tL));
    if n >= 1
        d = (tL(1:n) - tR(1:n))/Fs;
        lag = median(d);
        if abs(lag) <= maxLag_s && (n < 2 || (max(d)-min(d)) < 1.0), return; end
    end

    a = a0(i1:i2); b = b0(i1:i2);
    a = a - median(a); b = b - median(b);
    [c,l] = xcorr(b,a,round(min(maxLag_s,1.5)*Fs),'coeff');
    [~,i] = max(c); lag = l(i)/Fs;
end

function loc = picosGrandes(y,minDist)
    loc = [];
    if numel(y) < 2*minDist, return; end
    [~,lc,~,pr] = findpeaks(y(:),'MinPeakDistance',minDist);
    if isempty(lc), return; end
    loc = lc(pr >= 0.5*max(pr));
end

function rv = rotvecRel(qa,qb,rest)
    valid = all(isfinite([qa qb]),2);
    if ~any(valid)
        rv = NaN(numel(valid),3); return;     % sensor sin senal
    end
    qa(~valid,:) = repmat([1 0 0 0],nnz(~valid),1);
    qb(~valid,:) = repmat([1 0 0 0],nnz(~valid),1);
    A = quaternion(qa(:,1),qa(:,2),qa(:,3),qa(:,4));
    B = quaternion(qb(:,1),qb(:,2),qb(:,3),qb(:,4));
    R = conj(A).*B;
    r0 = rest & valid;
    if nnz(r0) < 10, r0 = false(size(valid)); r0(find(valid,200)) = true; end
    Rc = conj(meanrot(R(r0))).*R;
    [w,qx,qy,qz] = parts(Rc);
    sg = ones(size(w)); sg(w < 0) = -1;
    Rc = quaternion(sg.*w,sg.*qx,sg.*qy,sg.*qz);
    rv = rotvecd(Rc);
    rv(~valid,:) = NaN;
end

function graficoBarrasEMG(T,ejs,nomEj,musculos,nomMus,prefijo,etiquetaY,titulo)
    nM = numel(musculos); nE = numel(ejs); M = nan(nM,nE); S = nan(nM,nE);
    for ie = 1:nE
        sel = T.Ejercicio == string(ejs{ie});
        for im = 1:nM
            v = T.([prefijo musculos{im} '_pctMVC'])(sel);
            M(im,ie) = mean(v,'omitnan'); S(im,ie) = std(v,'omitnan');
        end
    end
    b = bar(M,'grouped'); hold on;
    for ie = 1:nE, errorbar(b(ie).XEndPoints,M(:,ie),S(:,ie),'k','LineStyle','none','CapSize',4); end
    yline(100,'--r','100 % MVC');
    set(gca,'XTick',1:nM,'XTickLabel',nomMus,'XTickLabelRotation',25);
    ylabel(etiquetaY); grid on; title(titulo); legend(b,nomEj,'Location','best');
end

function graficoBarrasLado(T,ejs,nomEj,varD,varI,etiquetaY,titulo)
    nE = numel(ejs); M = nan(nE,2); S = nan(nE,2);
    for ie = 1:nE
        sel = T.Ejercicio == string(ejs{ie});
        M(ie,:) = [mean(T.(varD)(sel),'omitnan') mean(T.(varI)(sel),'omitnan')];
        S(ie,:) = [std(T.(varD)(sel),'omitnan')  std(T.(varI)(sel),'omitnan')];
    end
    if nE == 1, M = [M; nan(1,2)]; S = [S; nan(1,2)]; end
    b = bar(M,'grouped'); hold on;
    for k = 1:2, errorbar(b(k).XEndPoints,M(:,k),S(:,k),'k','LineStyle','none','CapSize',4); end
    xlim([0.5 nE+0.5]);
    set(gca,'XTick',1:nE,'XTickLabel',nomEj);
    ylabel(etiquetaY); grid on; title(titulo); legend(b,{'Derecha','Izquierda'},'Location','best');
end

function reps = segmentarRepeticiones(x,iStart,iEnd,Fs,distMin_s,promMin,fracProm,incluirIncompleta,centrado,tolCentrado)
    % centrado = false: repeticion = valle -> valle (cinematica).
    % centrado = true : repeticion centrada en cada pico; limites = punto medio entre picos consecutivos
    %                   (+-P/2 en los extremos). Pensado para la envolvente del EMG.
    if nargin < 9, centrado = false; end
    if nargin < 10, tolCentrado = 0.25; end
    reps = zeros(0,2);
    idx = iStart:iEnd; y = x(idx); y = y(:);
    y = fillmissing(y,'linear','EndValues','nearest');
    if numel(y) < 2*round(distMin_s*Fs) || any(~isfinite(y)), return; end
    [~,lp,~,pr] = findpeaks(y,'MinPeakDistance',round(distMin_s*Fs),'MinPeakProminence',promMin);
    if isempty(lp), return; end
    lp = lp(pr >= fracProm*max(pr));
    if isempty(lp), return; end
    nP = numel(lp);
    if nP >= 2, P = round(median(diff(lp))); else, P = round(2.5*Fs); end

    if centrado
        lim = zeros(nP+1,1);
        lim(1)    = lp(1) - round(P/2);
        lim(2:nP) = round((lp(1:end-1) + lp(2:end))/2);
        lim(nP+1) = lp(nP) + round(P/2);
        tol = round(tolCentrado*P);
        for k = 1:nP
            fuera = (lim(k) < 1 - tol) || (lim(k+1) > numel(y) + tol);
            if fuera && ~incluirIncompleta, continue; end
            a = max(1,lim(k)); b = min(numel(y),lim(k+1));
            reps(end+1,:) = (idx(1)-1) + [a b]; %#ok<AGROW>
        end
        return;
    end

    valle = zeros(nP+1,1);
    % primer valle: ultimo punto cercano a la linea base ANTES de la subida
    a = max(1,lp(1)-P); segI = y(a:lp(1)); mnI = min(segI);
    kI = find(segI <= mnI + 0.15*(y(lp(1))-mnI),1,'last');
    if isempty(kI), [~,kI] = min(segI); end
    valle(1) = a+kI-1;
    for k = 1:nP-1, [~,m] = min(y(lp(k):lp(k+1))); valle(k+1) = lp(k)+m-1; end
    b = min(numel(y),lp(nP)+P); [~,m] = min(y(lp(nP):b)); valle(nP+1) = lp(nP)+m-1;
    incompleta = valle(nP+1) >= b-2;
    % Si la grabacion termina justo al acabar la ultima repeticion (valle en la ultima muestra pero ya
    % en la base del movimiento), se acepta como completa (en P5 ED3 perdia su 5.a repeticion).
    % v3.2: umbral 0,25 -> 0,45 (ED3 termina en ~0 grados con minimo global de ~-25 y no se rescataba).
    mnG = min(y);
    if incompleta && b >= numel(y) && y(valle(nP+1)) <= mnG + 0.45*(y(lp(nP)) - mnG)
        incompleta = false;
    end
    nRep = nP; if incompleta && ~incluirIncompleta, nRep = nP-1; end
    for k = 1:nRep, reps(end+1,:) = (idx(1)-1) + [valle(k) valle(k+1)]; end %#ok<AGROW>
end

function plotBanda(x,M,c,nombre,indiv)
    if nargin >= 5 && indiv
        plot(x,M','Color',0.55*c+0.45,'LineWidth',0.5,'HandleVisibility','off');
    end
    mu = mean(M,1,'omitnan'); sd = std(M,0,1,'omitnan');
    if size(M,1) < 2, sd = zeros(size(mu)); end
    ok = isfinite(mu) & isfinite(sd);
    if any(ok)
        fill([x(ok) fliplr(x(ok))],[mu(ok)+sd(ok) fliplr(mu(ok)-sd(ok))],c,'FaceAlpha',0.15, ...
            'EdgeColor','none','HandleVisibility','off');
    end
    plot(x,mu,'Color',c,'LineWidth',1.8,'DisplayName',nombre);
end

function datos = cargarCSV(archivo)
    % Prueba varias combinaciones de delimitador/decimal. NO elimina columnas vacias: en P5 las
    % columnas 34:37 (muslo I) estan vacias y quitarlas desplazaria todos los indices.
    combos = {{';',','},{';','.'},{',','.'},{'\t','.'},{'\t',','}};
    datos = []; d = [];
    for k = 1:numel(combos)
        try
            d = readmatrix(archivo,'Delimiter',combos{k}{1},'DecimalSeparator',combos{k}{2});
        catch
            continue;
        end
        if isempty(d) || size(d,2) < 1, continue; end
        d = d(~isnan(d(:,1)),:);
        if size(d,2) >= 49 && ~isempty(d)
            datos = d;
            if k > 1
                fprintf('  %s leído con delimitador "%s" y decimal "%s"\n',archivo,combos{k}{1},combos{k}{2});
            end
            return;
        end
    end
    if ~isempty(d)
        fprintf('  %s: ninguna combinación dio 49 columnas (mejor intento: %d).\n',archivo,size(d,2));
    end
end

function [y,unidad] = procesarEMG(x,Fs,fLow,fHigh,ventanaRMS_s,marcarHuecos)
    if nargin < 6, marcarHuecos = false; end
    x = double(x(:));
    y = NaN(size(x)); unidad = "sin datos";
    if ~any(isfinite(x)), return; end                 % canal vacio
    [x,unidad] = armonizarUnidadEMG(x);
    huecoLargo = false(size(x));
    if marcarHuecos
        h = quitarTramosCortos(isnan(x),round(0.05*Fs));
        huecoLargo = movmax(double(h),2*round(0.125*Fs)+1) > 0;
    end
    x = fillmissing(x,'linear','EndValues','nearest');
    [b,a] = butter(4,[fLow fHigh]/(Fs/2),'bandpass'); x = filtfilt(b,a,x);
    N = max(1,round(ventanaRMS_s*Fs));
    y = sqrt(movmean(x.^2,N,'omitnan'));
    y(huecoLargo) = NaN;
end

function [val,info] = calcularMVC(archivos,columna,Fs,fLow,fHigh,ventanaRMS_s,fracMin,nombreM)
    vals = NaN(numel(archivos),1);
    info = struct('nEnsayos',numel(archivos),'nValidos',0,'nDescartados',0,'ratio',NaN);
    for k = 1:numel(archivos)
        f = archivos{k};
        if ~isfile(f), error('Falta el archivo MVC %s.',f); end
        d = cargarCSV(f);
        if size(d,2) < columna, error('%s no contiene la columna %d.',f,columna); end
        [y,uni] = procesarEMG(d(:,columna),Fs,fLow,fHigh,ventanaRMS_s);
        m = round(0.5*Fs); if numel(y) > 2*m, y = y(m+1:end-m); end
        vals(k) = max(y,[],'omitnan');
        fprintf('%s | %s | columna %d | unidad original %s | MVC RMS=%.5g uV\n',f,nombreM,columna,uni,vals(k));
    end
    if all(~isfinite(vals) | vals == 0)
        warning('%s: MVC sin señal en TODOS los ensayos (canal desconectado).',nombreM);
        val = NaN; return;
    end
    ok = vals >= fracMin*max(vals);
    if any(~ok)
        warning('%s: descartados %d ensayo(s) (sin señal o con escala incompatible): %s.',nombreM,nnz(~ok), ...
            strjoin(archivos(~ok),', '));
    end
    val = max(vals(ok),[],'omitnan');
    info.nValidos = nnz(ok); info.nDescartados = nnz(~ok);
    if nnz(ok) > 1, info.ratio = max(vals(ok))/min(vals(ok)); end
    if isfinite(info.ratio) && info.ratio > 3
        warning('%s: ensayos de MVC poco consistentes (max/min = %.1f).',nombreM,info.ratio);
    end
    if isempty(val) || ~isfinite(val) || val <= 0, val = NaN; end
end

function x = rellenarHuecos(x,maxGap)
    x = logical(x(:)); if maxGap <= 0 || ~any(x), return; end
    z = diff([false;x;false]); a = find(z==1); b = find(z==-1)-1;
    for k = 1:numel(a)-1
        gap = a(k+1)-b(k)-1;
        if gap > 0 && gap <= maxGap, x(b(k)+1:a(k+1)-1) = true; end
    end
end

function x = quitarTramosCortos(x,minLen)
    x = logical(x(:)); if ~any(x), return; end
    z = diff([false;x;false]); a = find(z==1); b = find(z==-1)-1;
    for k = 1:numel(a), if b(k)-a(k)+1 < minLen, x(a(k):b(k)) = false; end, end
end

function r = rangoSeguro(x)
    x = x(isfinite(x)); if isempty(x), r = NaN; else, r = max(x)-min(x); end
end
