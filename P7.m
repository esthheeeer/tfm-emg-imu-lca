%% ANALISIS TFM (LCA): EMG + IMU + MVC - MEDIA POR EJERCICIO  (v3.1, P7)
%
%LADO AFECTADO: DERECHO
clear; clc; close all;

%% ============================================================
% 1. CONFIGURACION GENERAL
% =============================================================
paciente    = 'P7';
ladoOperado = 'D';      % 'D'   

mvcManual = struct();   % Ejemplo: mvcManual.VM_I = 150;

FsEMG = 2000; fLow = 20; fHigh = 450; ventanaRMS_s = 0.250;

archivosTarea = {'S17.csv','S27.csv', ...
                 'ED17.csv','ED27.csv', ...
                 'EI17.csv','EI27.csv'};

nombreEjercicio = containers.Map( ...
    {'S',                  'ED',               'EI'}, ...
    {'Sentarse-levantarse','Ejercicio ED',     'Ejercicio EI'});

% P7: sin muslo I (y sin pelvis): se segmenta SIEMPRE con la rodilla D
modoSegmentacion = containers.Map({'S','ED','EI'},{'D','D','D'});

% Deteccion automatica del reposo
ventanaReposo_s  = 1.5;
busquedaReposo_s = 10;
reposoManual = containers.Map('KeyType','char','ValueType','any');   % ej.: reposoManual('S27.csv') = [3 5];

% [v3] pelvisUnica: 'no' | 'D' | 'I'. Si 'I' se usa la pelvis I como referencia de AMBAS caderas
% (util si la pelvis D no tiene datos pero la I si); 'D' al reves. En P7 no hay ninguna pelvis valida.
pelvisUnica = 'no';

ejePorArchivo = true;
maxHuecoQ_s   = 1.0;

% Calidad de datos
maxVelArticular_dps = 800;
minValidoLado       = 0.5;
marcarHuecosEMG     = true;
excluirLado = containers.Map('KeyType','char','ValueType','any'); % ej.: excluirLado('S27.csv') = 'I';

ocultarMusculosSinMVC  = true;   % true = sin MVC valido se excluyen (NaN)
limiteArtefactoEMG_pct = Inf;    % ej.: 250

% Intervalo activo
umbralMovimiento_deg    = 8;
duracionMinMovimiento_s = 0.25;
rellenoHuecos_s         = 0.20;

% Repeticiones
distanciaMinPicos_s  = 0.8;     % valor por defecto
% distancia minima entre picos por ejercicio (evita doble conteo)
% EI: 1,8 s (periodo real ~2,5 s; las jorobas secundarias de la rodilla quedan a ~1-1,4 s del pico).
distanciaMinPicosEj = containers.Map({'S','ED','EI'},{0.8,0.8,1.8});   % VERIFICAR tras ver la segmentacion de P7
prominenciaMin_deg   = 8;
fraccionProminencia  = 0.5;
incluirRepIncompleta = false;   % valor por defecto
% Repeticion final "incompleta" por ejercicio. En S el intervalo activo termina justo cuando la
% rodilla vuelve a ~0 y la ultima repeticion era descartada; se incluye. En ED/EI (series cortadas al
% final del archivo, p. ej. ED27 y EI17) se mantiene descartada.
incluirRepEj = containers.Map({'S','ED','EI'},{true,false,false});
depurarPicos = true;            % [v3.1] imprime tiempos y prominencias de los picos detectados
fracMinDuracionRep   = 0.5;     % [v3] descarta repeticiones < 50 % de la mediana
excluirRep = containers.Map('KeyType','char','ValueType','any');   % ej.: excluirRep('ED27.csv') = [5.9 6.9];
nPuntos = 101;

% Desfase izquierda-derecha (solo ejercicios simetricos)
alinearLados         = true;
ejerciciosSimetricos = {'S'};
maxLagLados_s        = 4.5;
umbralValidezAlinear = 0.8;
umbralLagAlinear     = 0.1;     % [v3] no se alinea si |lag| < 0,1 s
lagManual = containers.Map('KeyType','char','ValueType','any');   % ej.: lagManual('S17.csv') = 0.70;

% EI17: la rodilla se mueve a ~3,2 s y ~6,5-7 s sin actividad del cuadriceps (previo a la serie);
% la serie con EMG empieza a ~8 s. Se recorta el intervalo activo.   % VERIFICAR con anotaciones/video
recorteManual = containers.Map('KeyType','char','ValueType','any');
recorteManual('EI17.csv') = [7.3 16.2];

fracMinEnsayoMVC  = 0.05;
fracMinMVCvsTarea = 0.02;
maxRatioMVC       = 3;          % [v3] inconsistente si max/min > 3

% Figuras
figurasPorArchivo        = false;
figurasMovimientoReal    = true;
figurasMediaPorEjercicio = true;
figurasComparacion       = true;
mostrarFigurasEnPantalla = false;
crearFigurasVisibles     = false;
setappdata(0,'visFig',ifelse(crearFigurasVisibles,'on','off'));
carpetaFiguras           = [paciente '_figuras'];
if ~isfolder(carpetaFiguras), mkdir(carpetaFiguras); end

ladoSano = ifelse(strcmp(ladoOperado,'I'),'D','I');

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

col.GM_D = 2;  col.VM_D = 8;  col.VL_D = 9;  col.BF_D = 14;
col.GM_I = 20; col.VM_I = 32; col.VL_I = 33; col.BF_I = 44;
col.qS1 = 4:7;   % pelvis derecha
col.qS2 = 10:13; % muslo derecho
col.qS4 = 22:25; % pelvis izquierda
col.qS5 = 28:31; % tibia derecha
col.qS6 = 34:37; % muslo izquierdo   (P7: sin datos)
col.qS7 = 40:43; % tibia izquierda

vars = {'hipFlexD','hipFlexI','kneeFlexD','kneeFlexI', ...
        'VM_D','VL_D','VM_I','VL_I','GM_D','GM_I','BF_D','BF_I'};

%% ============================================================
% 3. MVC
% =============================================================
archivosMVC.GM_D = {'GMD7.csv'};
archivosMVC.GM_I = {'GMI7.csv'};
archivosMVC.BF_D = {'ID7.csv'};
archivosMVC.BF_I = {'II7.csv'};
archivosMVC.CUAD = {'MVC17.csv'};

fprintf('\n=== MVC %s ===\n',paciente);
mvc = struct(); mvcOrigen = struct(); mvcInfo = struct(); mvcIncons = struct();
UN = [];   % registro de unidades originales
for j = 1:numel(musculos)
    m = musculos{j};
    if startsWith(m,'VM') || startsWith(m,'VL'), lista = archivosMVC.CUAD; else, lista = archivosMVC.(m); end
    [mvc.(m),info] = calcularMVC(lista,col.(m),FsEMG,fLow,fHigh,ventanaRMS_s,fracMinEnsayoMVC,maxRatioMVC,m);
    mvcInfo.(m) = info; mvcOrigen.(m) = "MVC";
    mvcIncons.(m) = isfinite(info.ratio) && info.ratio > maxRatioMVC;
    for k = 1:numel(lista)
        u = struct('Archivo',string(lista{k}),'Musculo',string(m),'Unidad_original',string(info.unidades{k}));
        UN = [UN; u]; %#ok<AGROW>
    end
end

%% ============================================================
% 4. FASE 1: PROCESAR CADA ARCHIVO
% =============================================================
SIG = {};
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

    [~,base] = fileparts(archivo);
    ej = regexprep(base,'\d+[A-Za-z]?$','');

    rmsEMG = struct();
    for j = 1:numel(musculos)
        m = musculos{j};
        [xe,un] = armonizarUnidadEMG(datos(:,col.(m)));       % [v3]
        UN = [UN; struct('Archivo',string(archivo),'Musculo',string(m),'Unidad_original',un)]; %#ok<AGROW>
        rmsEMG.(m) = procesarEMG(xe,FsEMG,fLow,fHigh,ventanaRMS_s,marcarHuecosEMG);
        pn = 100*mean(isnan(rmsEMG.(m)));
        if pn > 1, fprintf('  Aviso EMG: %s con %.1f %% de muestras perdidas (huecos > 50 ms)\n',nombreMusculo(m),pn); end
    end

    qP_D = limpiarQ(datos(:,col.qS1),Fs,maxHuecoQ_s); qM_D = limpiarQ(datos(:,col.qS2),Fs,maxHuecoQ_s); qT_D = limpiarQ(datos(:,col.qS5),Fs,maxHuecoQ_s);
    qP_I = limpiarQ(datos(:,col.qS4),Fs,maxHuecoQ_s); qM_I = limpiarQ(datos(:,col.qS6),Fs,maxHuecoQ_s); qT_I = limpiarQ(datos(:,col.qS7),Fs,maxHuecoQ_s);

    Qall = {qP_D,qM_D,qT_D,qP_I,qM_I,qT_I};
    pNV = zeros(1,6);
    for k = 1:6, pNV(k) = 100*mean(~all(isfinite(Qall{k}),2)); end
    fprintf('  %% no válido por sensor (%s): %s\n',strjoin(nomSensor,', '),sprintf('%.1f ',pNV));

    % [v3] pelvisUnica
    if strcmp(pelvisUnica,'I'), qP_D = qP_I; fprintf('  pelvisUnica = I: la pelvis I sirve de referencia de ambas caderas\n');
    elseif strcmp(pelvisUnica,'D'), qP_I = qP_D; fprintf('  pelvisUnica = D: la pelvis D sirve de referencia de ambas caderas\n'); end

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
    sig.rms = rmsEMG; sig.rv = rv; sig.restD = restD; sig.restI = restI; sig.pNV = pNV;
    SIG{end+1} = sig; %#ok<SAGROW>
end
if isempty(SIG), error('No se ha procesado ningún archivo.'); end
writetable(struct2table(UN),[paciente '_unidades_EMG_originales.csv']);

%% ============================================================
% 5. EJES DE FLEXO-EXTENSION (SVD) - GLOBAL y POR ARCHIVO
% =============================================================
fprintf('\n=== Ejes de flexión-extensión ===\n');
jn = {'hipD','hipI','kneeD','kneeI'};
eje = struct(); filasEje = [];
for j = 1:numel(jn)
    X = []; Xs = []; expl = NaN;
    for is = 1:numel(SIG)
        r = SIG{is}.rv.(jn{j});
        r = r(all(isfinite(r),2) & sqrt(sum(r.^2,2)) > 5,:);
        r = r(1:10:end,:);
        X = [X; r]; %#ok<AGROW>
        if strcmp(SIG{is}.ejercicio,'S'), Xs = [Xs; r]; end %#ok<AGROW>
    end
    g = struct(); g.Archivo = "GLOBAL"; g.Articulacion = string(jn{j});
    if size(X,1) < 50
        warning('Articulación %s SIN datos suficientes de movimiento: quedará en NaN.',jn{j});
        eje.(jn{j}) = [NaN NaN NaN];
        g.ex = NaN; g.ey = NaN; g.ez = NaN; g.VarExplicada = NaN; g.CosConGlobal = NaN;
        g.SignoAmbiguo = false; g.Metodo = "sin datos"; g.RhoCaderaRodilla = NaN;
        filasEje = [filasEje; g]; %#ok<AGROW>
        continue;
    end
    [~,S,V] = svd(X,'econ');
    ax = V(:,1);
    expl = S(1,1)^2/sum(diag(S).^2);
    if startsWith(jn{j},'hip') && size(Xs,1) > 50, Xref = Xs; else, Xref = X; end
    P = Xref*ax;
    if prctile(P,99) < -prctile(P,1), ax = -ax; end
    eje.(jn{j}) = ax(:)';
    fprintf('GLOBAL %s: eje=[% .2f % .2f % .2f], varianza explicada=%.0f %%\n',jn{j},ax,100*expl);
    g.ex = ax(1); g.ey = ax(2); g.ez = ax(3); g.VarExplicada = expl; g.CosConGlobal = 1;
    g.SignoAmbiguo = false; g.Metodo = "global"; g.RhoCaderaRodilla = NaN;
    filasEje = [filasEje; g]; %#ok<AGROW>
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
        amb = false;
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
            if isfinite(rho) && abs(rho) > 0.2
                if rho < 0, ax = -ax; end
                metodo = 'corr rodilla';
            else
                if prctile(P,99) < -prctile(P,1), ax = -ax; end
                metodo = 'excursión';
            end
            P = r*ax'; a99 = prctile(P,99); a1 = -prctile(P,1);
            amb = strcmp(metodo,'excursión') && min(a99,a1) > 0.6*max(a99,a1);
            if expl < 0.85
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
        g = struct(); g.Archivo = string(SIG{is}.archivo); g.Articulacion = string(jname);
        g.ex = ax(1); g.ey = ax(2); g.ez = ax(3); g.VarExplicada = expl;
        g.CosConGlobal = dotG; g.SignoAmbiguo = amb; g.Metodo = string(metodo); g.RhoCaderaRodilla = rho;
        filasEje = [filasEje; g]; %#ok<AGROW>
    end
end
tablaEjes = struct2table(filasEje);
writetable(tablaEjes,[paciente '_ejes_articulares.csv']);

%% ============================================================
% 6. ANGULOS + CALIDAD + INTERVALO ACTIVO
% =============================================================
CAL = [];
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
        warning('%s: lado DERECHO (IMU) excluido (válido %.0f %%).',s.archivo,100*fD);
        s.hipFlexD(:) = NaN; s.kneeFlexD(:) = NaN; fD = 0;
    end
    if exI || fI < minValidoLado
        warning('%s: lado IZQUIERDO (IMU) excluido (válido %.0f %%).',s.archivo,100*fI);
        s.hipFlexI(:) = NaN; s.kneeFlexI(:) = NaN; fI = 0;
    end
    fprintf('%s: datos válidos en zona activa D=%.0f %%, I=%.0f %%\n',s.archivo,100*fD,100*fI);

    %  desfase izquierda-derecha ----
    lagAuto = 0;
    if min(fD,fI) > 0.2, lagAuto = lagIzqVsDer(s.kneeFlexD,s.kneeFlexI,Fs,maxLagLados_s); end
    s.lagIzq = lagAuto;
    if min(fD,fI) > 0.2
        fprintf('%s: lag rodilla I vs D = %+.2f s (>0 = izquierda retrasada)\n',s.archivo,lagAuto);
        if abs(lagAuto) >= 0.95*maxLagLados_s
            warning('%s: lag en el límite de búsqueda (%.1f s); posible emparejamiento desplazado.',s.archivo,maxLagLados_s);
        end
    end
    esSim = any(strcmp(s.ejercicio,ejerciciosSimetricos));
    if isKey(lagManual,s.archivo)
        s.lagIzq = lagManual(s.archivo);
        fprintf('   -> lag MANUAL %+.2f s (sustituye al automático %+.2f s)\n',s.lagIzq,lagAuto);
    end
    lagAplicado = 0;
    if alinearLados && esSim && min(fD,fI) >= umbralValidezAlinear && abs(s.lagIzq) >= umbralLagAlinear
        c0 = corrDI(s.kneeFlexD,s.kneeFlexI);
        desf = @(y) interp1(s.t,y,s.t + s.lagIzq,'linear',NaN);
        s.hipFlexI = desf(s.hipFlexI); s.kneeFlexI = desf(s.kneeFlexI);
        for mm = {'VM_I','VL_I','GM_I','BF_I'}, s.rms.(mm{1}) = desf(s.rms.(mm{1})); end
        c1 = corrDI(s.kneeFlexD,s.kneeFlexI);
        lagAplicado = s.lagIzq;
        fprintf('   -> señal izquierda alineada con la derecha (%+.2f s; correlación D-I %.2f -> %.2f)\n',s.lagIzq,c0,c1);
    elseif esSim
        s.lagIzq = 0;
    end

    mx = max(abs([s.hipFlexD; s.hipFlexI; s.kneeFlexD; s.kneeFlexI]),[],'omitnan');
    if ~isempty(mx) && isfinite(mx) && mx > 180, warning('%s: ángulo > 180° (%.0f°). Revisar sensores.',s.archivo,mx); end

    [s.iStart,s.iEnd] = intervaloActivo(s.kneeFlexD,s.kneeFlexI,Fs,umbralMovimiento_deg,rellenoHuecos_s,duracionMinMovimiento_s);
    if isKey(recorteManual,s.archivo)
        rc = recorteManual(s.archivo);
        s.iStart = find(s.t >= rc(1),1,'first'); s.iEnd = find(s.t <= rc(2),1,'last');
        fprintf('%s: recorte manual %.1f - %.1f s\n',s.archivo,rc(1),rc(2));
    end

    %  calidad cinematica por archivo ----
    c = struct(); c.Archivo = string(s.archivo); c.Ejercicio = string(s.ejercicio);
    c.NoValido_PelvisD_pct = s.pNV(1); c.NoValido_MusloD_pct = s.pNV(2); c.NoValido_TibiaD_pct = s.pNV(3);
    c.NoValido_PelvisI_pct = s.pNV(4); c.NoValido_MusloI_pct = s.pNV(5); c.NoValido_TibiaI_pct = s.pNV(6);
    c.ValidoZonaActiva_D_pct = 100*fD; c.ValidoZonaActiva_I_pct = 100*fI;
    c.LagAuto_s = lagAuto; c.LagAplicado_s = lagAplicado;
    CAL = [CAL; c]; %#ok<AGROW>
    SIG{is} = s;
end
writetable(struct2table(CAL),[paciente '_calidad_cinematica_por_archivo.csv']);

%% ============================================================
% 7. MVC DEFINITIVO Y %MVC
% =============================================================
fprintf('\n=== Validación del MVC frente a las tareas ===\n');
for j = 1:numel(musculos)
    m = musculos{j};
    picoTarea = 0;
    for is = 1:numel(SIG), picoTarea = max(picoTarea,prctile(SIG{is}.rms.(m),99.9)); end
    if isfield(mvcManual,m) && ~isempty(mvcManual.(m))
        fprintf('MVC %s sustituido manualmente: %.5g -> %.5g\n',m,mvc.(m),mvcManual.(m));
        mvc.(m) = mvcManual.(m); mvcOrigen.(m) = "Manual"; mvcIncons.(m) = false;
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
        if isfinite(limiteArtefactoEMG_pct), s.(m)(s.(m) > limiteArtefactoEMG_pct) = NaN; end
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
    if isKey(modoSegmentacion,ej), modo = modoSegmentacion(ej); else, modo = 'ambas'; end
    if isKey(distanciaMinPicosEj,ej), dMin = distanciaMinPicosEj(ej); else, dMin = distanciaMinPicos_s; end
    if isKey(incluirRepEj,ej), incRep = incluirRepEj(ej); else, incRep = incluirRepIncompleta; end   % [v3.1]
    fDs = mean(isfinite(s.kneeFlexD(s.iStart:s.iEnd))); fIs = mean(isfinite(s.kneeFlexI(s.iStart:s.iEnd)));
    switch modo
        case 'D'
            if fDs < 0.5 && fIs >= 0.5, xSeg = s.kneeFlexI; modo = 'I (sustituye a D)'; else, xSeg = s.kneeFlexD; end
        case 'I'
            if fIs < 0.5 && fDs >= 0.5, xSeg = s.kneeFlexD; modo = 'D (sustituye a I)'; else, xSeg = s.kneeFlexI; end
        otherwise
            if min(fDs,fIs) >= 0.8, xSeg = mean([s.kneeFlexD s.kneeFlexI],2,'omitnan');
            elseif fDs >= fIs, xSeg = s.kneeFlexD; modo = 'D (automático)';
            else, xSeg = s.kneeFlexI; modo = 'I (automático)'; end
    end
    if depurarPicos, fprintf('%s: intervalo activo %.2f - %.2f s | distMin %.2f s | repIncompleta=%d\n', ...
            s.archivo,s.t(s.iStart),s.t(s.iEnd),dMin,incRep); end
    reps = segmentarRepeticiones(xSeg,s.iStart,s.iEnd,s.Fs,dMin,prominenciaMin_deg, ...
        fraccionProminencia,incRep,s.t,depurarPicos);
    if ~isempty(reps)
        keep = false(size(reps,1),1);
        for k = 1:size(reps,1), keep(k) = mean(isfinite(xSeg(reps(k,1):reps(k,2)))) >= 0.9; end
        if any(~keep), fprintf('  %s: %d repetición(es) descartada(s) por huecos en la señal de segmentación\n',s.archivo,nnz(~keep)); end
        reps = reps(keep,:);
    end
    if ~isempty(reps)      % [v3] repeticiones demasiado cortas
        dur = (reps(:,2)-reps(:,1))/s.Fs; md = median(dur);
        cort = dur < fracMinDuracionRep*md;
        if any(cort)
            fprintf('   %s: DESCARTADAS %d repeticion(es) < %.0f %% de la mediana (%.2f s): %s s\n', ...
                s.archivo,nnz(cort),100*fracMinDuracionRep,md,sprintf('%.2f ',dur(cort)));
            reps = reps(~cort,:);
        end
    end
    if ~isempty(reps) && isKey(excluirRep,s.archivo)   % [v3] ventanas manuales
        w = excluirRep(s.archivo); exr = false(size(reps,1),1);
        for k = 1:size(reps,1)
            tk = s.t(reps(k,:));
            for q = 1:size(w,1), if tk(1) < w(q,2) && tk(2) > w(q,1), exr(k) = true; end, end
        end
        if any(exr)
            fprintf('   EXCLUIDAS %d repeticion(es) de %s por ventana manual\n',nnz(exr),s.archivo);
            reps = reps(~exr,:);
        end
    end
    fprintf('%s (%s, segmentación "%s"): %d repeticiones válidas\n',s.archivo,nombreDe(nombreEjercicio,ej),modo,size(reps,1));
    for k = 1:size(reps,1)
        fprintf('   rep %d: %6.2f - %6.2f s (%.2f s)\n',k,s.t(reps(k,1)),s.t(reps(k,2)),(reps(k,2)-reps(k,1))/s.Fs);
    end
    if ~isempty(reps) && abs(s.lagIzq) > mean((reps(:,2)-reps(:,1))/s.Fs)
        warning('%s: |lag| (%.2f s) mayor que la duración media del ciclo; posible emparejamiento desplazado.',s.archivo,abs(s.lagIzq));
    end
    SIG{is}.reps = reps;

    for r = 1:size(reps,1)
        ia = reps(r,1); ib = reps(r,2);
        tr = s.t(ia:ib); tn = linspace(tr(1),tr(end),nPuntos);
        for v = 1:numel(vars)
            yv = s.(vars{v})(ia:ib);
            if mean(~isfinite(yv)) > 0.05, yv(:) = NaN; end
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
        g.MVC_RMS = mvc.(m); g.Origen_MVC = mvcOrigen.(m); g.N_repeticiones = nnz(sel);
        g.N_validas = nnz(isfinite(pico));
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
            g.(['ROM_' art{1} '_' lado{1} '_n'])         = nnz(isfinite(v));
            g.(['ROM_' art{1} '_' lado{1} '_media_deg']) = mean(v,'omitnan');
            g.(['ROM_' art{1} '_' lado{1} '_SD_deg'])    = std(v,'omitnan');
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
disp('COMPARACIÓN DERECHA vs IZQUIERDA (índice NO es el LSI):'); disp(tablaSim);

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

%% ============================================================
% 9B. [v3] RESUMEN GLOBAL (Op/Sana, Delta, LSI, Calidad 0/1/2)
% =============================================================
% S: misma serie, operada vs sana. Escalon: la operada se toma del ejercicio que INICIA la pierna operada
% y la sana del que inicia la sana (series distintas) -> comparacion orientativa.
ejOp = ifelse(strcmp(ladoOperado,'I'),'EI','ED'); ejSa = ifelse(strcmp(ladoOperado,'I'),'ED','EI');
filasRes = [];
for ib = 1:numel(paresBase)
    b = paresBase{ib};
    for tipo = {'Pico','Media'}
        for tarea = {'S','Step'}
            [selOp,selSa] = selTarea(T,tarea{1},ejOp,ejSa);
            vOp = T.([tipo{1} '_' b '_' ladoOperado '_pctMVC'])(selOp);
            vSa = T.([tipo{1} '_' b '_' ladoSano '_pctMVC'])(selSa);
            pOp = T.(['Pico_' b '_' ladoOperado '_pctMVC'])(selOp);
            pSa = T.(['Pico_' b '_' ladoSano '_pctMVC'])(selSa);
            [c1,m1] = calidadEMGlado(pOp,[b '_' ladoOperado],ladoOperado,mvcOrigen,mvcIncons);
            [c2,m2] = calidadEMGlado(pSa,[b '_' ladoSano],ladoSano,mvcOrigen,mvcIncons);
            filasRes = [filasRes; filaResumen(paciente,ladoOperado,[tipo{1} '_' b],tarea{1},vOp,vSa,min(c1,c2),[m1 m2])]; %#ok<AGROW>
        end
    end
end
for art = {'Cadera','Rodilla'}
    for tarea = {'S','Step'}
        [selOp,selSa] = selTarea(T,tarea{1},ejOp,ejSa);
        vOp = T.(['ROM_' art{1} '_' ladoOperado])(selOp);
        vSa = T.(['ROM_' art{1} '_' ladoSano])(selSa);
        nOp = nnz(isfinite(vOp)); nSa = nnz(isfinite(vSa));
        cal = 2; mot = {sprintf('n efectivo %d (op) / %d (sana)',nOp,nSa)};
        if nOp == 0 || nSa == 0, cal = 0; end
        % varianza explicada del eje de los archivos de la tarea
        if strcmp(tarea{1},'S'), ejL = {'S'}; else, ejL = {ejOp,ejSa}; end
        for lado = {ladoOperado,ladoSano}
            jnm = [ifelse(strcmp(art{1},'Cadera'),'hip','knee') lado{1}];
            [vmin,amb] = minVarEje(tablaEjes,SIG,jnm,ejL);
            if isfinite(vmin)
                if vmin < 0.60, cal = 0; mot{end+1} = sprintf('eje %s explica solo %.0f %%',jnm,100*vmin); %#ok<AGROW>
                elseif vmin < 0.85, cal = min(cal,1); mot{end+1} = sprintf('eje %s explica %.0f %%',jnm,100*vmin); end %#ok<AGROW>
            end
            if amb, cal = min(cal,1); mot{end+1} = ['signo ambiguo ' jnm]; end %#ok<AGROW>
        end
        filasRes = [filasRes; filaResumen(paciente,ladoOperado,['ROM_' art{1}],tarea{1},vOp,vSa,cal,mot)]; %#ok<AGROW>
    end
end
tablaRes = struct2table(filasRes);
writetable(tablaRes,[paciente '_resumen_global.csv']);
disp(tablaRes(:,{'Variable','Tarea','Op_media','San_media','LSI','Calidad','Motivo'}));

%% ============================================================
% 10A. MOVIMIENTO REAL POR EJERCICIO (4 filas x n series)
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
                        title(ax,sprintf('%s - Cadera flex-ext (lag I = %+.2f s)',q.archivo,q.lagIzq));
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
        nVD = nnz(any(isfinite(A.hipFlexD),2)); nVI = nnz(any(isfinite(A.hipFlexI),2));
        figMov = nuevaFigura(['Movimiento medio - ' nomEj{ie}],[100 50 850 1000]);
        tl = tiledlayout(figMov,4,1,'TileSpacing','compact');
        nexttile(tl); hold on;
        plotBanda(x,A.hipFlexD,c(1,:),'Derecha',true); plotBanda(x,A.hipFlexI,c(2,:),'Izquierda',true);
        grid on; xlim([0 100]); ylabel('Grados'); legend('Location','best');
        if nVD == 0 && nVI == 0   % [v3.1] panel de cadera sin datos
            text(0.5,0.5,'Sin datos válidos de cadera','Units','normalized','HorizontalAlignment','center', ...
                'FontSize',12,'Color',[0.4 0.4 0.4]);
        end
        title(sprintf('Cadera - flex-ext (n = %d repeticiones; válidas: D = %d, I = %d; grueso = media ± DE, fino = cada repetición)',nR,nVD,nVI));
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

fprintf('\nTerminado. Figuras en la carpeta "%s".\n',carpetaFiguras);
fprintf('Revisa %s_unidades_EMG_originales.csv, %s_ejes_articulares.csv, %s_calidad_cinematica_por_archivo.csv y el control de calidad EMG.\n',paciente,paciente,paciente);

%% ============================================================
% FUNCIONES LOCALES
% =============================================================
function v = ifelse(c,a,b)
    if c, v = a; else, v = b; end
end

function [x,unidad] = armonizarUnidadEMG(x)
    % [v3] Pasa el canal a uV segun la resolucion del ADC (0,298 -> uV; 0,000298 -> mV).
    x = double(x(:)); v = x(isfinite(x));
    if isempty(v) || all(v == 0)
        x = zeros(size(x)); unidad = "sin datos"; return;
    end
    v = v(1:min(numel(v),200000));
    u = unique(round(v,7)); d = diff(u); d = d(d > 5e-7);
    if isempty(d), unidad = "uV"; return; end
    if min(d) < 0.05, x = x*1000; unidad = "mV (x1000)"; else, unidad = "uV"; end
end

function c = corrDI(kD,kI)
    ok = isfinite(kD) & isfinite(kI);
    if nnz(ok) < 50, c = NaN; return; end
    cc = corrcoef(kD(ok),kI(ok)); c = cc(1,2);
end

function [selOp,selSa] = selTarea(T,tarea,ejOp,ejSa)
    if strcmp(tarea,'S')
        selOp = T.Ejercicio == "S"; selSa = selOp;
    else
        selOp = T.Ejercicio == string(ejOp); selSa = T.Ejercicio == string(ejSa);
    end
end

function [cal,mot] = calidadEMGlado(pico,m,lado,mvcOrigen,mvcIncons)
    % Calidad EMG de un lado: 0 = no analizable, 1 = orientativo, 2 = fiable
    cal = 2; mot = {};
    if startsWith(mvcOrigen.(m),"SIN")
        cal = 0; mot{end+1} = ['canal sin señal / sin MVC válido ' lado];
    end
    if all(~isfinite(pico)) || max(pico,[],'omitnan') < 5
        cal = 0; mot{end+1} = ['canal sin señal ' lado ' (pico < 5 %MVC)'];
    end
    if cal == 0, return; end
    if mvcIncons.(m), cal = min(cal,1); mot{end+1} = ['MVC inconsistente ' lado]; end
    frac = mean(pico(isfinite(pico)) > 100);
    if frac >= 0.2
        cal = min(cal,1); mot{end+1} = sprintf('%.0f %% de repeticiones con pico > 100 %% MVC',100*frac);
    elseif max(pico,[],'omitnan') < 15
        cal = min(cal,1); mot{end+1} = ['activación baja ' lado ' (pico < 15 %MVC)'];
    end
end

function f = filaResumen(pac,lado,variable,tarea,vOp,vSa,cal,mot)
    f = struct();
    f.Paciente = string(pac); f.LadoOperado = string(lado); f.Variable = string(variable); f.Tarea = string(tarea);
    f.Op_media = mean(vOp,'omitnan'); f.Op_SD = std(vOp,'omitnan'); f.Op_n = nnz(isfinite(vOp));
    f.San_media = mean(vSa,'omitnan'); f.San_SD = std(vSa,'omitnan'); f.San_n = nnz(isfinite(vSa));
    f.Delta = f.Op_media - f.San_media;
    if isfinite(f.Op_media) && isfinite(f.San_media) && f.San_media > 0
        f.LSI = 100*f.Op_media/f.San_media;
    else
        f.LSI = NaN;
    end
    if isnan(f.LSI), cal = 0; end
    f.Calidad = cal;
    f.Motivo = string(strjoin(mot,'; '));
end

function [vmin,amb] = minVarEje(tablaEjes,SIG,jname,ejList)
    vmin = NaN; amb = false;
    for is = 1:numel(SIG)
        if ~any(strcmp(SIG{is}.ejercicio,ejList)), continue; end
        k = tablaEjes.Archivo == string(SIG{is}.archivo) & tablaEjes.Articulacion == string(jname);
        if ~any(k), continue; end
        v = tablaEjes.VarExplicada(k);
        if isfinite(v), vmin = min([vmin v],[],'omitnan'); end
        amb = amb || any(tablaEjes.SignoAmbiguo(k));
    end
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

function q = limpiarQ(q,Fs,maxHueco_s)
    q = double(q);
    bad = any(~isfinite(q),2) | sqrt(sum(q.^2,2)) < 0.5;
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
    % [v3] usa solo los sensores con datos (>50 % validos); ignora los ausentes
    N = size(Qs{1},1); rest = false(N,1);
    Qs = Qs(cellfun(@(q) mean(all(isfinite(q),2)) > 0.5,Qs));
    if isempty(Qs), return; end
    sp = zeros(N,1); valid = true(N,1);
    for k = 1:numel(Qs)
        q = Qs{k}; valid = valid & all(isfinite(q),2);
        d = min(abs(sum(q(1:end-1,:).*q(2:end,:),2)),1);
        sp(2:end) = sp(2:end) + 2*acosd(d)*Fs;
    end
    if ~any(valid), return; end
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
        rv = NaN(numel(valid),3); return;
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
    b = bar(M,'grouped'); hold on;
    for k = 1:2, errorbar(b(k).XEndPoints,M(:,k),S(:,k),'k','LineStyle','none','CapSize',4); end
    set(gca,'XTick',1:nE,'XTickLabel',nomEj);
    ylabel(etiquetaY); grid on; title(titulo); legend(b,{'Derecha','Izquierda'},'Location','best');
end

function reps = segmentarRepeticiones(x,iStart,iEnd,Fs,distMin_s,promMin,fracProm,incluirIncompleta,t,depurar)
    % [v3.1] t y depurar: si depurar = true imprime tiempos y prominencias de los picos detectados.
    reps = zeros(0,2);
    idx = iStart:iEnd; y = x(idx); y = y(:);
    y = fillmissing(y,'linear','EndValues','nearest');
    if numel(y) < 2*round(distMin_s*Fs) || any(~isfinite(y)), return; end
    [~,lp,~,pr] = findpeaks(y,'MinPeakDistance',round(distMin_s*Fs),'MinPeakProminence',promMin);
    if isempty(lp), return; end
    if depurar
        fprintf('   picos detectados (t, prominencia): %s\n', ...
            sprintf('(%.2f s, %.0f°) ',[t(idx(lp))'; pr']));
    end
    lp = lp(pr >= fracProm*max(pr));
    if isempty(lp), return; end
    if depurar
        fprintf('   picos tras filtro de prominencia (>= %.0f %% del máx.): %s\n',100*fracProm, ...
            sprintf('%.2f ',t(idx(lp))));
    end
    nP = numel(lp);
    if nP >= 2, P = round(median(diff(lp))); else, P = round(2.5*Fs); end
    valle = zeros(nP+1,1);
    a = max(1,lp(1)-P); [~,m] = min(y(a:lp(1))); valle(1) = a+m-1;
    for k = 1:nP-1, [~,m] = min(y(lp(k):lp(k+1))); valle(k+1) = lp(k)+m-1; end
    b = min(numel(y),lp(nP)+P); [~,m] = min(y(lp(nP):b)); valle(nP+1) = lp(nP)+m-1;
    incompleta = valle(nP+1) >= b-2;
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
    datos = readmatrix(archivo,'Delimiter',';','DecimalSeparator',',');
    datos = datos(~isnan(datos(:,1)),:);
end

function y = procesarEMG(x,Fs,fLow,fHigh,ventanaRMS_s,marcarHuecos)
    if nargin < 6, marcarHuecos = false; end
    x = double(x(:));
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

function [val,info] = calcularMVC(archivos,columna,Fs,fLow,fHigh,ventanaRMS_s,fracMin,maxRatio,nombreM)
    vals = NaN(numel(archivos),1);
    info = struct('unidades',{cell(1,numel(archivos))},'nValidos',0,'ratio',NaN);
    for k = 1:numel(archivos)
        f = archivos{k};
        if ~isfile(f), error('Falta el archivo MVC %s.',f); end
        d = cargarCSV(f);
        if size(d,2) < columna, error('%s no contiene la columna %d.',f,columna); end
        [xe,un] = armonizarUnidadEMG(d(:,columna));            % [v3]
        info.unidades{k} = char(un);
        y = procesarEMG(xe,Fs,fLow,fHigh,ventanaRMS_s);
        m = round(0.5*Fs); if numel(y) > 2*m, y = y(m+1:end-m); end
        vals(k) = max(y,[],'omitnan');
        fprintf('%s | %s | columna %d | unidad original %s | MVC RMS=%.5g uV\n',f,nombreM,columna,un,vals(k));
    end
    if all(~isfinite(vals) | vals == 0)
        warning('%s: MVC sin señal en TODOS los ensayos (canal desconectado).',nombreM);
        val = NaN; return;
    end
    ok = vals >= fracMin*max(vals);
    if any(~ok)
        warning('%s: descartados %d ensayo(s) con escala incompatible (%s).',nombreM,nnz(~ok), ...
            strjoin(archivos(~ok),', '));
    end
    info.nValidos = nnz(ok);
    val = max(vals(ok),[],'omitnan');
    if nnz(ok) > 1
        info.ratio = max(vals(ok))/min(vals(ok));
        if info.ratio > maxRatio
            warning('%s: ensayos de MVC poco consistentes (max/min = %.1f).',nombreM,info.ratio);
        end
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
