package com.audiobookreader

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.zIndex
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.audiobookreader.data.Book
import com.audiobookreader.data.AppLanguage
import com.audiobookreader.data.ModelFamily
import com.audiobookreader.data.ModelCatalog
import com.audiobookreader.data.PocketVoice
import com.audiobookreader.data.TextChunker
import com.audiobookreader.data.TtsModelSpec
import com.audiobookreader.ui.theme.AppThemeMode
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

@Composable
fun AudiobookReaderApp(
    viewModel: ReaderViewModel,
    showBatteryOptimizationPrompt: Boolean = false,
    onRequestBatteryOptimization: () -> Unit = {},
    onDismissBatteryOptimization: () -> Unit = {},
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val strings = UiStrings.forLanguage(state.appLanguage)
    var tab by remember { mutableIntStateOf(0) }
    LaunchedEffect(tab) {
        if (tab == 1) viewModel.refreshOnlineVoices()
    }
    Scaffold(
        modifier = Modifier.statusBarsPadding(),
        bottomBar = {
            NavigationBar {
                NavigationBarItem(selected = tab == 0, onClick = { tab = 0 }, icon = { Text("📚") }, label = { Text(strings.library) })
                NavigationBarItem(selected = tab == 1, onClick = { tab = 1 }, icon = { Text("🔊") }, label = { Text(strings.models) })
                NavigationBarItem(selected = tab == 2, onClick = { tab = 2 }, icon = { Text("⚙") }, label = { Text(strings.settings) })
            }
        }
    ) { padding ->
        Surface(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                0 -> LibraryScreen(state, viewModel, strings)
                1 -> ModelScreen(state, viewModel, strings)
                else -> SettingsScreen(state, viewModel, strings, onRequestBatteryOptimization)
            }
        }
    }
    if (showBatteryOptimizationPrompt) {
        AlertDialog(
            onDismissRequest = onDismissBatteryOptimization,
            title = { Text(if (state.appLanguage == AppLanguage.SPANISH) "Permitir reproducción en segundo plano" else "Allow background playback") },
            text = { Text(if (state.appLanguage == AppLanguage.SPANISH) "Para seguir leyendo con la pantalla apagada o mientras usas otra aplicación, audiobookreader necesita quedar excluido de la optimización de batería. Android abrirá ahora la pantalla adecuada." else "To keep reading with the screen off or while you use another app, audiobookreader needs to be excluded from battery optimization. Android will now open the correct system screen.") },
            confirmButton = {
                Button(onClick = onRequestBatteryOptimization) {
                    Text(if (state.appLanguage == AppLanguage.SPANISH) "Abrir ajustes" else "Open settings")
                }
            },
            dismissButton = {
                TextButton(onClick = onDismissBatteryOptimization) {
                    Text(if (state.appLanguage == AppLanguage.SPANISH) "Ahora no" else "Not now")
                }
            },
        )
    }
    state.pendingEdgeModel?.let { pending ->
        val spanish = state.appLanguage == AppLanguage.SPANISH
        AlertDialog(
            onDismissRequest = viewModel::declineEdgeDisclosure,
            title = { Text(if (spanish) "Uso de Edge TTS online" else "Using online Edge TTS") },
            text = {
                Column(
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(pending.name, style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (spanish) {
                            "Solo al reproducir con Edge, los fragmentos de texto seleccionados y los ajustes de voz, idioma y velocidad se envían directamente a Microsoft mediante una conexión cifrada para generar el audio. Tus documentos completos, marcadores y audios de clonación no se envían. Puedes rechazarlo y usar modelos locales."
                        } else {
                            "Only when playing with Edge, selected text fragments and the voice, language, and speed settings are sent directly to Microsoft over an encrypted connection to generate audio. Full documents, bookmarks, and voice-cloning recordings are not sent. You can decline and use local models."
                        },
                    )
                    Text(
                        if (spanish) "Puedes retirar este consentimiento en Ajustes." else "You can revoke this consent in Settings.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            confirmButton = {
                Button(onClick = viewModel::acceptEdgeDisclosure) {
                    Text(if (spanish) "Aceptar y usar Edge" else "Accept and use Edge")
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::declineEdgeDisclosure) {
                    Text(if (spanish) "Rechazar" else "Decline")
                }
            },
        )
    }
}

@Composable
private fun LibraryScreen(state: ReaderState, viewModel: ReaderViewModel, strings: UiStrings) {
    var openedBookId by rememberSaveable { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(viewModel::importBook)
    }
    val openedBook = state.books.firstOrNull { it.id == openedBookId }
    if (openedBook != null) {
        BackHandler { openedBookId = null }
        BookDetailScreen(openedBook, state, viewModel, strings) { openedBookId = null }
        return
    }
    Box(Modifier.fillMaxSize()) {
        ShelfBackground()
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Text(strings.library, style = MaterialTheme.typography.headlineMedium)
                Text(strings.librarySubtitle)
                Spacer(Modifier.height(8.dp))
                Button(onClick = { picker.launch(arrayOf("application/pdf", "application/epub+zip", "text/plain", "text/html")) }) {
                    Text(strings.addBook)
                }
                state.message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            }
            if (state.books.isEmpty()) item { Text(strings.emptyLibrary) }
            items(state.books.chunked(2)) { row ->
                Row(Modifier.fillMaxWidth()) {
                    row.forEach { book -> BookCard(book, state, viewModel, strings, Modifier.weight(1f)) { openedBookId = book.id } }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ShelfBackground() {
    val shelfColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.28f)
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceVariant)) {
        Canvas(Modifier.fillMaxSize()) {
            var y = size.height * 0.30f
            while (y < size.height) {
                drawRect(shelfColor.copy(alpha = 0.16f), topLeft = androidx.compose.ui.geometry.Offset(0f, y), size = androidx.compose.ui.geometry.Size(size.width, 8f))
                drawLine(shelfColor, androidx.compose.ui.geometry.Offset(0f, y), androidx.compose.ui.geometry.Offset(size.width, y), strokeWidth = 3f)
                y += 300f
            }
        }
    }
}

@Composable
private fun BookCard(book: Book, state: ReaderState, viewModel: ReaderViewModel, strings: UiStrings, modifier: Modifier, onOpen: () -> Unit) {
    Card(modifier.padding(6.dp).clickable {
        viewModel.selectBook(book)
        onOpen()
    }) {
        Column(Modifier.padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            BookCover(book, Modifier.fillMaxWidth().height(190.dp))
            Spacer(Modifier.height(8.dp))
            Text(book.title, style = MaterialTheme.typography.titleMedium, maxLines = 2)
            val progress = state.progressByBook[book.id]
            Text(if (progress != null) "${progress.percentage}%" else strings.openBook)
        }
    }
}

@Composable
private fun BookCover(book: Book, modifier: Modifier) {
    val bitmap by produceState<Bitmap?>(initialValue = null, book.coverPath) {
        value = withContext(Dispatchers.IO) { book.coverPath?.let(::decodeCover) }
    }
    if (bitmap != null) {
        androidx.compose.foundation.Image(bitmap!!.asImageBitmap(), contentDescription = book.title, modifier = modifier, contentScale = ContentScale.Crop)
    } else {
        Box(modifier.background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Text("📖", fontSize = 42.sp) }
    }
}

private fun decodeCover(path: String): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sampleSize = 1
    while (bounds.outWidth / sampleSize > 900 || bounds.outHeight / sampleSize > 1200) sampleSize *= 2
    return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
        inSampleSize = sampleSize
        inPreferredConfig = Bitmap.Config.RGB_565
    })
}

@Composable
private fun BookDetailScreen(book: Book, state: ReaderState, viewModel: ReaderViewModel, strings: UiStrings, onBack: () -> Unit) {
    val chunks = remember(book.id) { book.chapters.flatMap { chapter -> TextChunker.split(chapter.text).map { Triple(chapter.id, chapter.title, it) } } }
    val listState = rememberLazyListState()
    val showScrollToTop by remember { derivedStateOf { listState.firstVisibleItemIndex > 4 } }
    val scrollScope = rememberCoroutineScope()
    val activeIndex = state.progress?.itemIndex ?: -1
    val chunksStartIndex = 2 + if (state.bookmarks.isNotEmpty()) 1 else 0
    var modelMenuExpanded by remember { mutableStateOf(false) }
    var voiceLanguageMenuExpanded by remember { mutableStateOf(false) }
    var voiceSettingsExpanded by rememberSaveable(book.id) { mutableStateOf(false) }
    var voiceLanguage by rememberSaveable(book.id) { mutableStateOf(preferredVoiceLanguage(state)) }
    var speed by remember(book.id) { mutableFloatStateOf(state.bookTtsSettings.speed) }
    var speedText by rememberSaveable(book.id) { mutableStateOf("%.2f".format(state.bookTtsSettings.speed)) }
    var referenceText by remember(book.id) { mutableStateOf(state.bookTtsSettings.referenceText) }
    var seekFraction by remember { mutableFloatStateOf(0f) }
    var seeking by remember { mutableStateOf(false) }
    val referencePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(viewModel::importReferenceAudio)
    }
    val selectableVoiceModels = state.availableModels.filter {
        it.family == ModelFamily.EDGE || it.id in state.installed
    }
    val voiceLanguages = buildSet {
        selectableVoiceModels.mapTo(this) { it.language }
        if (selectableVoiceModels.any { it.family == ModelFamily.KOKORO && it.id in state.installed }) {
            ModelCatalog.kokoroVoices.mapTo(this) { it.language }
        }
    }.filter { it != "all" }.sortedBy(strings::languageLabel)
    val localVoiceModels = selectableVoiceModels.filter {
        it.family != ModelFamily.EDGE && (it.language == voiceLanguage || it.language == "all")
    }.sortedWith(compareBy<TtsModelSpec> { recentModelRank(state, it.id) }
        .thenBy { strings.languageLabel(it.language) }.thenBy { it.family.ordinal }.thenBy { it.name })
    val onlineVoiceModels = selectableVoiceModels.filter {
        it.family == ModelFamily.EDGE && it.language == voiceLanguage
    }.sortedWith(compareBy<TtsModelSpec> { recentModelRank(state, it.id) }.thenBy { it.name })
    LaunchedEffect(state.selectedModel.id) {
        val language = preferredVoiceLanguage(state)
        if (language != "all") voiceLanguage = language
    }
    LaunchedEffect(state.progress?.positionMs, state.currentDurationMs, seeking) {
        if (!seeking && state.currentDurationMs > 0L) {
            seekFraction = ((state.progress?.positionMs ?: 0L).toFloat() / state.currentDurationMs.toFloat()).coerceIn(0f, 1f)
        }
    }
    LaunchedEffect(state.bookTtsSettings.speed) {
        speed = state.bookTtsSettings.speed
        speedText = "%.2f".format(state.bookTtsSettings.speed)
    }
    Box(Modifier.fillMaxSize()) {
        LazyColumn(state = listState, modifier = Modifier.fillMaxSize().padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            TextButton(onClick = onBack) { Text("‹ ${strings.library}") }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                BookCover(book, Modifier.size(width = 120.dp, height = 170.dp).clip(MaterialTheme.shapes.medium))
                Column(Modifier.weight(1f)) {
                    Text(book.title, style = MaterialTheme.typography.headlineSmall)
                    Text("${book.chapters.size} ${strings.chapters}")
                    Text("${strings.voice}: ${state.selectedModel.name}")
                    if (state.selectedModel.family == ModelFamily.KOKORO) {
                        ModelCatalog.kokoroVoices.firstOrNull { it.available && it.speakerId == state.bookTtsSettings.speakerId }?.let { voice ->
                            Text(kokoroVoiceLabel(voice, strings), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(strings.voiceSettings, style = MaterialTheme.typography.titleMedium)
            OutlinedButton(
                onClick = { voiceSettingsExpanded = !voiceSettingsExpanded },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (voiceSettingsExpanded) "⚙  ${strings.voiceSettings}  ▲" else "⚙  ${strings.voiceSettings}  ▼")
            }
            if (voiceSettingsExpanded) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(strings.voice, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            if (state.appLanguage == AppLanguage.SPANISH) "Idioma del modelo o voz" else "Model or voice language",
                            style = MaterialTheme.typography.labelLarge,
                        )
                        Box {
                            OutlinedButton(onClick = { voiceLanguageMenuExpanded = true }, modifier = Modifier.fillMaxWidth()) {
                                Text(strings.languageLabel(voiceLanguage))
                            }
                            DropdownMenu(expanded = voiceLanguageMenuExpanded, onDismissRequest = { voiceLanguageMenuExpanded = false }) {
                                voiceLanguages.forEach { code ->
                                    SeparatedDropdownOption(
                                        title = strings.languageLabel(code),
                                        selected = code == voiceLanguage,
                                        onClick = { voiceLanguage = code; voiceLanguageMenuExpanded = false },
                                    )
                                }
                            }
                        }
                        Box {
                            Button(onClick = { modelMenuExpanded = true }, modifier = Modifier.fillMaxWidth()) { Text(state.selectedModel.name, maxLines = 1) }
                            DropdownMenu(expanded = modelMenuExpanded, onDismissRequest = { modelMenuExpanded = false }) {
                                DropdownMenuItem(
                                    text = { Text(if (state.appLanguage == AppLanguage.SPANISH) "LOCAL · DESCARGADOS" else "LOCAL · DOWNLOADED", fontWeight = FontWeight.Bold) },
                                    onClick = {}, enabled = false,
                                )
                                if (localVoiceModels.isEmpty()) {
                                    DropdownMenuItem(
                                        text = { Text(if (state.appLanguage == AppLanguage.SPANISH) "No hay modelos locales descargados para este idioma" else "No downloaded local models for this language") },
                                        onClick = {}, enabled = false,
                                    )
                                }
                                localVoiceModels.forEach { model ->
                                    SeparatedDropdownOption(
                                        title = model.name,
                                        subtitle = "${model.family.label()} · ${strings.languageLabel(model.language)} · LOCAL",
                                        selected = model.id == state.selectedModel.id,
                                        onClick = {
                                            viewModel.selectModel(model)
                                            if (model.family == ModelFamily.KOKORO) {
                                                ModelCatalog.kokoroVoices.firstOrNull { it.language == voiceLanguage && it.available }
                                                    ?.let { viewModel.setBookSpeakerId(it.speakerId) }
                                            }
                                            modelMenuExpanded = false
                                        },
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("ONLINE · EDGE TTS", fontWeight = FontWeight.Bold) },
                                    onClick = {}, enabled = false,
                                )
                                if (onlineVoiceModels.isEmpty()) {
                                    DropdownMenuItem(
                                        text = { Text(if (state.appLanguage == AppLanguage.SPANISH) "No hay voces online para este idioma" else "No online voices for this language") },
                                        onClick = {}, enabled = false,
                                    )
                                }
                                onlineVoiceModels.forEach { model ->
                                    SeparatedDropdownOption(
                                        title = model.name.removePrefix("Edge · "),
                                        subtitle = "Edge TTS · ${strings.languageLabel(model.language)} · ONLINE",
                                        selected = model.id == state.selectedModel.id,
                                        onClick = { viewModel.selectModel(model); modelMenuExpanded = false },
                                    )
                                }
                            }
                        }
                        Text("${strings.speed}: ${"%.2f".format(speed)}x", style = MaterialTheme.typography.labelLarge)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Slider(
                                value = speed,
                                onValueChange = {
                                    speed = (it * 20f).roundToInt() / 20f
                                    speedText = "%.2f".format(speed)
                                },
                                onValueChangeFinished = { viewModel.setBookSpeed(speed) },
                                valueRange = 0.5f..2.5f,
                                steps = 39,
                                modifier = Modifier.weight(1f),
                            )
                            OutlinedTextField(
                                value = speedText,
                                onValueChange = { value ->
                                    if (value.length <= 4 && value.matches(Regex("[0-9]?[.,]?[0-9]{0,2}"))) {
                                        speedText = value
                                        value.replace(',', '.').toFloatOrNull()?.takeIf { it in 0.5f..2.5f }?.let { speed = it }
                                    }
                                },
                                label = { Text("x") },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
                                keyboardActions = KeyboardActions(onDone = {
                                    speedText.replace(',', '.').toFloatOrNull()?.coerceIn(0.5f, 2.5f)?.let {
                                        speed = it
                                        speedText = "%.2f".format(it)
                                        viewModel.setBookSpeed(it)
                                    }
                                }),
                                modifier = Modifier.width(92.dp),
                            )
                        }
                        OutlinedButton(
                            onClick = {
                                speedText.replace(',', '.').toFloatOrNull()?.coerceIn(0.5f, 2.5f)?.let {
                                    speed = it
                                    speedText = "%.2f".format(it)
                                    viewModel.setBookSpeed(it)
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text(strings.applyVoiceSettings) }
                        if (state.selectedModel.family == ModelFamily.KOKORO) {
                            KokoroVoicePicker(state, viewModel, strings)
                        } else if (state.selectedModel.family == ModelFamily.SUPERTONIC) {
                            SupertonicVoicePicker(state, viewModel)
                        } else if (state.selectedModel.family == ModelFamily.POCKET) {
                            if (state.selectedModel.presetVoices.isNotEmpty()) {
                                PocketVoicePicker(state, viewModel, strings)
                            } else {
                                Text(
                                    if (state.appLanguage == AppLanguage.SPANISH) {
                                        "PocketTTS usa el audio de referencia seleccionado."
                                    } else {
                                        "PocketTTS uses the selected reference audio."
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        } else if (state.selectedModel.family == ModelFamily.ZIPVOICE) {
                            Text(
                                if (state.appLanguage == AppLanguage.SPANISH) {
                                    "ZipVoice usa el audio de referencia y su transcripción exacta."
                                } else {
                                    "ZipVoice uses the reference audio and its exact transcript."
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            Text(
                                if (state.appLanguage == AppLanguage.SPANISH) {
                                    "La voz es el modelo seleccionado: ${state.selectedModel.name}"
                                } else {
                                    "The voice is the selected model: ${state.selectedModel.name}"
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (state.selectedModel.referenceAudioRequired) {
                            Text(
                                if (state.appLanguage == AppLanguage.SPANISH) "Clonación de voz" else "Voice cloning",
                                style = MaterialTheme.typography.labelLarge,
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                OutlinedButton(
                                    onClick = { referencePicker.launch(arrayOf("audio/wav", "audio/x-wav")) },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text(
                                        if (state.bookTtsSettings.referenceAudioPath.isBlank()) {
                                            if (state.appLanguage == AppLanguage.SPANISH) "Elegir audio WAV de referencia" else "Choose reference WAV audio"
                                        } else {
                                            if (state.appLanguage == AppLanguage.SPANISH) "Audio de referencia seleccionado" else "Reference audio selected"
                                        },
                                        maxLines = 1,
                                    )
                                }
                                OutlinedButton(
                                    onClick = viewModel::clearReferenceAudio,
                                    enabled = state.bookTtsSettings.referenceAudioPath.isNotBlank(),
                                    modifier = Modifier.weight(0.55f),
                                ) {
                                    Text(if (state.appLanguage == AppLanguage.SPANISH) "Borrar" else "Clear")
                                }
                            }
                            if (state.selectedModel.referenceTextRequired) {
                                OutlinedTextField(
                                    value = referenceText,
                                    onValueChange = { referenceText = it; viewModel.setBookReferenceText(it) },
                                    label = { Text(if (state.appLanguage == AppLanguage.SPANISH) "Transcripción exacta del audio" else "Exact reference transcript") },
                                    supportingText = { Text(if (state.appLanguage == AppLanguage.SPANISH) "ZipVoice necesita que coincida con el audio." else "ZipVoice requires this to match the audio.") },
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                }
            }
        }
        item {
            state.message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            state.progress?.let {
                val displayedFragment = if (it.itemCount <= 0) 0 else it.itemIndex.coerceIn(0, it.itemCount - 1) + 1
                Text("${strings.savedProgress}: ${it.percentage}% · ${strings.fragment} $displayedFragment/${it.itemCount}")
            }
            state.cacheStatus?.let { Text("${strings.audioReady}: ${it.percentage}% · ${it.sizeLabel}") }
            Text(strings.autoSave, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(
                onClick = {
                    scrollScope.launch {
                        listState.animateScrollToItem(chunksStartIndex + activeIndex)
                    }
                },
                enabled = activeIndex in chunks.indices,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (state.appLanguage == AppLanguage.SPANISH) "Ir al punto actual" else "Go to current position")
            }
            if (state.currentDurationMs > 0L && activeIndex in state.readyChunks) {
                Text(strings.seekPosition, style = MaterialTheme.typography.titleSmall)
                Slider(
                    value = seekFraction,
                    onValueChange = { seeking = true; seekFraction = it },
                    onValueChangeFinished = {
                        seeking = false
                        viewModel.seekCurrentPosition((seekFraction * state.currentDurationMs).toLong())
                    },
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(formatDuration((seekFraction * state.currentDurationMs).toLong()), style = MaterialTheme.typography.bodySmall)
                    Text(formatDuration(state.currentDurationMs), style = MaterialTheme.typography.bodySmall)
                }
            }
            if (state.generating) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(strings.preparing)
            } else {
                val startLabel = state.pendingStartIndex?.let { " · ${strings.fragment} ${it + 1}" }.orEmpty()
                Button(onClick = { viewModel.playSelected() }, modifier = Modifier.fillMaxWidth()) { Text("▶ ${strings.play}$startLabel") }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { viewModel.jumpToChunk(activeIndex - 1) },
                    enabled = activeIndex > 0 && state.readyChunks.contains(activeIndex - 1),
                    modifier = Modifier.weight(1f),
                ) { Text("‹ ${strings.previousFragment}", maxLines = 1) }
                OutlinedButton(
                    onClick = { viewModel.jumpToChunk(activeIndex + 1) },
                    enabled = activeIndex >= 0 && activeIndex < chunks.lastIndex && state.readyChunks.contains(activeIndex + 1),
                    modifier = Modifier.weight(1f),
                ) { Text("${strings.nextFragment} ›", maxLines = 1) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = viewModel::addBookmark, modifier = Modifier.weight(1f)) { Text(strings.addBookmark, maxLines = 1) }
                OutlinedButton(onClick = viewModel::resetSelectedBookProgress, modifier = Modifier.weight(1f)) { Text(strings.resetProgress, maxLines = 1) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = viewModel::stopSelectedPlayback, modifier = Modifier.weight(1f)) { Text(strings.stop, maxLines = 1) }
                OutlinedButton(onClick = viewModel::clearSelectedBookCache, modifier = Modifier.weight(1f)) { Text(strings.clearAudio, maxLines = 1) }
            }
            OutlinedButton(onClick = viewModel::clearAllAudioCache, modifier = Modifier.fillMaxWidth()) { Text(strings.clearCache) }
        }
        if (state.bookmarks.isNotEmpty()) {
            item {
                Text(strings.bookmarks, style = MaterialTheme.typography.titleMedium)
                state.bookmarks.forEach { Text("• ${it.label}") }
            }
        }
        itemsIndexed(chunks) { index, chunk ->
            val active = activeIndex == index
            val selected = state.pendingStartIndex == index
            Column(
                Modifier.fillMaxWidth()
                    .clickable { viewModel.selectChunkForPlayback(index) }
                    .then(
                        when {
                            active -> Modifier.border(2.dp, MaterialTheme.colorScheme.primary, MaterialTheme.shapes.medium).padding(16.dp)
                            selected -> Modifier.border(2.dp, MaterialTheme.colorScheme.secondary, MaterialTheme.shapes.medium).padding(14.dp)
                            else -> Modifier.padding(vertical = 8.dp)
                        }
                    )
            ) {
                Text(if (active) "${chunk.second} · ${strings.readingNow}" else chunk.second, style = MaterialTheme.typography.titleMedium, color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal)
                Spacer(Modifier.height(7.dp))
                Text(chunk.third, style = MaterialTheme.typography.bodyLarge.copy(fontSize = if (active) 22.sp else 18.sp, lineHeight = if (active) 34.sp else 29.sp, lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None)), color = MaterialTheme.colorScheme.onSurface)
                if (selected) Text(strings.tapToPlayFragment, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
                if (!active && index < chunks.lastIndex) Divider(Modifier.padding(top = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
            }
        }
        }
        if (showScrollToTop) {
            FloatingActionButton(
                onClick = { scrollScope.launch { listState.animateScrollToItem(0) } },
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 10.dp)
                    .size(56.dp)
                    .shadow(8.dp, MaterialTheme.shapes.large)
                    .zIndex(2f),
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Text("↑", fontSize = 28.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun ModelScreen(state: ReaderState, viewModel: ReaderViewModel, strings: UiStrings) {
    val uriHandler = LocalUriHandler.current
    var expanded by remember { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var installedOnly by rememberSaveable { mutableStateOf(false) }
    var localExpanded by rememberSaveable { mutableStateOf(true) }
    var onlineExpanded by rememberSaveable { mutableStateOf(true) }
    var pendingLicenseModel by remember { mutableStateOf<TtsModelSpec?>(null) }
    var pendingDeleteModel by remember { mutableStateOf<TtsModelSpec?>(null) }
    val languages = state.availableModels.map { it.language }.filter { it != "all" }.distinct().sorted()
    val normalizedQuery = query.trim().lowercase()
    val visibleModels = state.availableModels.asSequence()
        .filter { state.modelLanguageFilter == "all" || it.language == state.modelLanguageFilter || it.language == "all" }
        .filter { !installedOnly || it.family == ModelFamily.EDGE || it.id in state.installed }
        .filter { normalizedQuery.isBlank() || listOf(it.name, it.family.label(), it.language, it.edgeVoice)
            .any { value -> normalizedQuery in value.lowercase() } }
        .sortedWith(compareByDescending<TtsModelSpec> { it.id == state.selectedModel.id }
            .thenByDescending { it.id in state.installed }
            .thenBy { recentModelRank(state, it.id) }
            .thenBy { it.family.ordinal }
            .thenBy { it.name })
        .toList()
    val localModels = visibleModels.filter { it.family != ModelFamily.EDGE }
    val onlineModels = visibleModels.filter { it.family == ModelFamily.EDGE }
    LazyColumn(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Text(strings.models, style = MaterialTheme.typography.headlineMedium)
            Text(strings.modelsSubtitle)
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text(if (state.appLanguage == AppLanguage.SPANISH) "Buscar modelo o voz" else "Search models or voices") },
                singleLine = true,
                trailingIcon = {
                    if (query.isNotEmpty()) TextButton(onClick = { query = "" }) { Text("×", fontSize = 22.sp) }
                },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            Box {
                Button(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("${if (state.appLanguage == AppLanguage.SPANISH) "Idioma" else "Language"}: ${strings.languageLabel(state.modelLanguageFilter)}")
                }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(text = { Text(strings.allLanguages) }, onClick = { viewModel.setModelLanguageFilter("all"); expanded = false })
                    languages.forEach { code -> DropdownMenuItem(text = { Text(strings.languageLabel(code)) }, onClick = { viewModel.setModelLanguageFilter(code); expanded = false }) }
                }
            }
            OutlinedButton(onClick = { installedOnly = !installedOnly }) {
                Text((if (installedOnly) "✓ " else "") + if (state.appLanguage == AppLanguage.SPANISH) "Descargados y disponibles" else "Downloaded and available")
            }
            if (state.downloading != null || state.downloadQueue.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    if (state.appLanguage == AppLanguage.SPANISH) {
                        "Descargas: ${if (state.downloading != null) "1 activa" else "ninguna activa"} · ${state.downloadQueue.size} en cola"
                    } else {
                        "Downloads: ${if (state.downloading != null) "1 active" else "none active"} · ${state.downloadQueue.size} queued"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item(key = "local-heading") {
            ModelSectionHeader(
                title = if (state.appLanguage == AppLanguage.SPANISH) "Modelos locales" else "Local models",
                subtitle = if (state.appLanguage == AppLanguage.SPANISH) "Se descargan una vez y funcionan sin conexión" else "Download once and use offline",
                count = localModels.size,
                expanded = localExpanded,
                onToggle = { localExpanded = !localExpanded },
            )
        }
        if (localExpanded) {
            items(localModels, key = { "local-${it.id}" }) { spec ->
                ModelCard(spec, state, viewModel, strings,
                    onLicenseRequired = { pendingLicenseModel = it },
                    onDeleteRequested = { pendingDeleteModel = it })
            }
        }
        item(key = "online-heading") {
            ModelSectionHeader(
                title = if (state.appLanguage == AppLanguage.SPANISH) "Voces online" else "Online voices",
                subtitle = "Edge TTS · ${if (state.appLanguage == AppLanguage.SPANISH) "sin descarga, requiere Internet" else "no download, Internet required"}",
                count = onlineModels.size,
                expanded = onlineExpanded,
                onToggle = { onlineExpanded = !onlineExpanded },
            )
        }
        if (onlineExpanded) {
            items(onlineModels, key = { "online-${it.id}" }) { spec ->
                ModelCard(spec, state, viewModel, strings,
                    onLicenseRequired = { pendingLicenseModel = it },
                    onDeleteRequested = { pendingDeleteModel = it })
            }
        }
        if (visibleModels.isEmpty()) {
            item { Text(if (state.appLanguage == AppLanguage.SPANISH) "No hay modelos que coincidan con estos filtros." else "No models match these filters.") }
        }
    }
    pendingLicenseModel?.let { spec ->
        val spanish = state.appLanguage == AppLanguage.SPANISH
        AlertDialog(
            onDismissRequest = { pendingLicenseModel = null },
            title = { Text(if (spanish) "Condiciones de uso del modelo" else "Model usage terms") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(spec.name, style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (spanish) {
                            "Este modelo tiene condiciones de licencia que debes revisar antes de descargarlo."
                        } else {
                            "This model has license terms you must review before downloading it."
                        }
                    )
                    Text("License: ${spec.licenseSpdx}")
                    if (spec.attribution.isNotBlank()) Text("Attribution: ${spec.attribution}")
                    Text(
                        if (spanish) {
                            "Al aceptar, confirmas que usarás el modelo respetando sus condiciones, incluyendo cualquier restricción de uso, atribución o ShareAlike aplicable."
                        } else {
                            "By accepting, you confirm that you will use the model according to its terms, including any applicable use restrictions, attribution, or ShareAlike requirements."
                        }
                    )
                    if (spec.referenceAudioRequired) {
                        Text(
                            if (spanish) {
                                "Usa únicamente voces para las que tengas permiso. No utilices la clonación para suplantar, engañar o perjudicar a otras personas."
                            } else {
                                "Only use voices you have permission to use. Do not use voice cloning to impersonate, deceive, or harm other people."
                            },
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    if (spec.licenseUrl.isNotBlank()) {
                        TextButton(onClick = { uriHandler.openUri(spec.licenseUrl) }) {
                            Text(if (spanish) "Abrir licencia completa" else "Open full license")
                        }
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    viewModel.downloadModel(spec)
                    pendingLicenseModel = null
                }) {
                    Text(if (spanish) "Aceptar y descargar" else "Accept and download")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingLicenseModel = null }) {
                    Text(if (spanish) "Rechazar" else "Reject")
                }
            },
        )
    }
    pendingDeleteModel?.let { spec ->
        val spanish = state.appLanguage == AppLanguage.SPANISH
        AlertDialog(
            onDismissRequest = { pendingDeleteModel = null },
            title = { Text(if (spanish) "Eliminar modelo descargado" else "Delete downloaded model") },
            text = { Text(if (spanish)
                "Se eliminarán los archivos de ${spec.name}. Si este paquete se comparte entre idiomas o modos de voz, se eliminará para todos ellos. Los libros, el progreso y el audio ya generado se conservarán."
                else "The files for ${spec.name} will be deleted. If this package is shared by languages or voice modes, it will be removed for all of them. Books, progress, and generated audio will be preserved.") },
            confirmButton = {
                Button(onClick = { viewModel.deleteModel(spec); pendingDeleteModel = null }) {
                    Text(if (spanish) "Eliminar" else "Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeleteModel = null }) {
                    Text(if (spanish) "Cancelar" else "Cancel")
                }
            },
        )
    }
}

@Composable
private fun ModelSectionHeader(
    title: String,
    subtitle: String,
    count: Int,
    expanded: Boolean,
    onToggle: () -> Unit,
) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onToggle)) {
        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("$title ($count)", style = MaterialTheme.typography.titleLarge)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(if (expanded) "▲" else "▼")
        }
    }
}

@Composable
private fun ModelCard(
    spec: TtsModelSpec,
    state: ReaderState,
    viewModel: ReaderViewModel,
    strings: UiStrings,
    onLicenseRequired: (TtsModelSpec) -> Unit,
    onDeleteRequested: (TtsModelSpec) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
            Text(spec.name, style = MaterialTheme.typography.titleMedium)
            Text("${if (spec.family == ModelFamily.EDGE) "Edge TTS" else if (spec.archiveName.isBlank() && spec.remoteFiles.isEmpty()) strings.imported else spec.family.label()} · ${strings.languageLabel(spec.language)}")
            if (spec.id == "kokoro-multi-v1-0") {
                Text(if (state.appLanguage == AppLanguage.SPANISH)
                    "Una descarga compartida · 54 voces · Inglés, español, francés, hindi, italiano, japonés, portugués y chino. Elige Dora, Alex o Santa en Configuración de voz del libro."
                    else "One shared download · 54 voices · English, Spanish, French, Hindi, Italian, Japanese, Portuguese and Chinese. Choose Dora, Alex or Santa in the book's Voice settings.")
            }
            if (spec.family == ModelFamily.SUPERTONIC) {
                Text("One shared download · 31 languages · 10 voices (M1–M5, F1–F5)")
            }
            if (spec.family == ModelFamily.POCKET) {
                Text(if (spec.referenceAudioRequired) {
                    if (state.appLanguage == AppLanguage.SPANISH) "Clonación · elige una muestra WAV limpia de 3–30 segundos en Configuración de voz. Comparte descarga con las voces predefinidas de este idioma."
                    else "Voice cloning · choose a clean 3–30 second reference WAV in Voice settings. Shares the download with preset voices in this language."
                } else {
                    if (state.appLanguage == AppLanguage.SPANISH) "Voces predefinidas · elige una voz por nombre en Configuración de voz. No necesita tu audio de referencia."
                    else "Preset voices · choose a voice by name in Voice settings. No personal reference audio is needed."
                })
            }
            if (spec.family == ModelFamily.ZIPVOICE) {
                Text("Chinese + English voice cloning · reference WAV and exact transcript required")
            }
            if (spec.experimental) Text(strings.experimental)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                if (state.selectedModel.id == spec.id) Text("${strings.selected}  ")
                TextButton(
                    onClick = { viewModel.selectModel(spec) },
                    enabled = spec.family == ModelFamily.EDGE || spec.id in state.installed,
                ) { Text(strings.use) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                if (spec.family == ModelFamily.EDGE) {
                    Text("ONLINE", color = Color(0xFF2E7D32), fontWeight = FontWeight.Bold)
                } else if (state.deletingModel == spec.storageId) {
                    Text(if (state.appLanguage == AppLanguage.SPANISH) "Eliminando…" else "Deleting…")
                } else if (state.installed.contains(spec.id)) {
                    Text(strings.downloaded)
                    TextButton(
                        onClick = { onDeleteRequested(spec) },
                        enabled = state.downloading == null && state.deletingModel == null,
                    ) { Text(if (state.appLanguage == AppLanguage.SPANISH) "Eliminar" else "Delete", color = MaterialTheme.colorScheme.error) }
                }
                else if (state.downloading == spec.id) {
                    Text("${state.downloadProgress}% · ${if (state.downloadProgress < 60) "Downloading" else "Extracting / installing"}")
                }
                else if (spec.storageId in state.downloadQueue) {
                    val position = state.downloadQueue.indexOf(spec.storageId) + 1
                    TextButton(onClick = { viewModel.removeQueuedDownload(spec) }) {
                        Text(
                            if (state.appLanguage == AppLanguage.SPANISH) "En cola #$position · Quitar"
                            else "Queued #$position · Remove",
                        )
                    }
                }
                else TextButton(enabled = state.deletingModel == null, onClick = {
                    if (spec.requiresAcceptance) onLicenseRequired(spec) else viewModel.downloadModel(spec)
                }) { Text(strings.download) }
            }
            if (state.downloading == spec.id) LinearProgressIndicator((state.downloadProgress / 100f).coerceIn(0f, 1f), Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun KokoroVoicePicker(state: ReaderState, viewModel: ReaderViewModel, strings: UiStrings) {
    var expanded by remember { mutableStateOf(false) }
    val voices = ModelCatalog.kokoroVoices
    val selected = voices.firstOrNull { it.available && it.speakerId == state.bookTtsSettings.speakerId }
    Text(
        if (state.appLanguage == AppLanguage.SPANISH) "Voz de Kokoro" else "Kokoro voice",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Box {
        Button(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Text(selected?.let { kokoroVoiceLabel(it, strings) } ?: "Speaker ${state.bookTtsSettings.speakerId}", maxLines = 1)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            voices.groupBy { it.language }.forEach { (language, group) ->
                DropdownMenuItem(
                    modifier = Modifier.background(MaterialTheme.colorScheme.surfaceVariant),
                    text = { Text(strings.languageLabel(language), fontWeight = FontWeight.Bold) },
                    onClick = {},
                    enabled = false,
                )
                group.forEach { voice ->
                    SeparatedDropdownOption(
                        title = kokoroVoiceName(voice),
                        subtitle = "${strings.languageLabel(voice.language)} · ${kokoroVoiceGender(voice, state.appLanguage)} · ${voice.id}",
                        selected = voice.available && voice.speakerId == state.bookTtsSettings.speakerId,
                        onClick = {
                            if (voice.available) {
                                viewModel.setBookSpeakerId(voice.speakerId)
                                expanded = false
                            }
                        },
                        enabled = voice.available,
                    )
                }
            }
        }
    }
}

@Composable
private fun SupertonicVoicePicker(state: ReaderState, viewModel: ReaderViewModel) {
    var expanded by remember { mutableStateOf(false) }
    val selected = ModelCatalog.supertonicVoices.getOrNull(state.bookTtsSettings.speakerId)
        ?: ModelCatalog.supertonicVoices.first()
    Text(
        if (state.appLanguage == AppLanguage.SPANISH) "Voz de Supertonic" else "Supertonic voice",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Box {
        Button(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Text(selected, maxLines = 1)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            ModelCatalog.supertonicVoices.forEachIndexed { index, voice ->
                SeparatedDropdownOption(
                    title = voice,
                    subtitle = supertonicVoiceDescription(voice, state.appLanguage),
                    selected = index == state.bookTtsSettings.speakerId,
                    onClick = {
                        viewModel.setBookSpeakerId(index)
                        expanded = false
                    },
                )
            }
        }
    }
    Text(
        if (state.appLanguage == AppLanguage.SPANISH) "La voz se aplica al idioma Supertonic seleccionado."
        else "The voice is applied to the selected Supertonic language.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun PocketVoicePicker(state: ReaderState, viewModel: ReaderViewModel, strings: UiStrings) {
    var expanded by remember { mutableStateOf(false) }
    val voices = state.selectedModel.presetVoices
    val selected = voices.getOrNull(state.bookTtsSettings.speakerId) ?: voices.first()
    Text(
        if (state.appLanguage == AppLanguage.SPANISH) "Voz de PocketTTS" else "PocketTTS voice",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Box {
        Button(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Text(pocketVoiceLabel(selected), maxLines = 1)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            voices.forEachIndexed { index, voice ->
                SeparatedDropdownOption(
                    title = pocketVoiceLabel(voice),
                    subtitle = strings.languageLabel(voice.language),
                    selected = index == state.bookTtsSettings.speakerId,
                    onClick = {
                        viewModel.setBookSpeakerId(index)
                        expanded = false
                    },
                )
            }
        }
    }
    Text(
        if (state.appLanguage == AppLanguage.SPANISH) {
            "La muestra de esta voz predefinida se descarga en la primera reproducción."
        } else {
            "The preset voice sample is downloaded on first playback."
        },
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun SeparatedDropdownOption(
    title: String,
    subtitle: String? = null,
    selected: Boolean,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val background = if (selected) {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.72f)
    } else {
        Color.Transparent
    }
    Column(Modifier.fillMaxWidth().background(background)) {
        DropdownMenuItem(
            modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = (if (selected) "✓  " else "") + title,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
                    )
                    subtitle?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (selected) {
                                MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.82f)
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                }
            },
            onClick = onClick,
            enabled = enabled,
        )
        Divider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.75f))
    }
}

private fun kokoroVoiceName(voice: com.audiobookreader.data.KokoroVoice): String = when (voice.id) {
    "ef_dora" -> "Dora"
    "em_alex" -> "Alex"
    "em_santa" -> "Santa"
    else -> voice.id.substringAfter('_').replace('_', ' ').replaceFirstChar { it.uppercase() }
}

private fun kokoroVoiceGender(
    voice: com.audiobookreader.data.KokoroVoice,
    language: AppLanguage,
): String {
    val female = voice.id.substringBefore('_').endsWith('f')
    return if (language == AppLanguage.SPANISH) {
        if (female) "Voz femenina" else "Voz masculina"
    } else {
        if (female) "Female voice" else "Male voice"
    }
}

private fun supertonicVoiceDescription(voice: String, language: AppLanguage): String {
    val female = voice.firstOrNull()?.uppercaseChar() == 'F'
    val number = voice.drop(1)
    return if (language == AppLanguage.SPANISH) {
        "Voz ${if (female) "femenina" else "masculina"} $number"
    } else {
        "${if (female) "Female" else "Male"} voice $number"
    }
}

private fun kokoroVoiceLabel(voice: com.audiobookreader.data.KokoroVoice, strings: UiStrings): String = when (voice.id) {
    "ef_dora", "em_alex", "em_santa" -> "${kokoroVoiceName(voice)} · ${strings.languageLabel("es")}"
    else -> "${kokoroVoiceName(voice)} · ${strings.languageLabel(voice.language)}"
}

private fun pocketVoiceLabel(voice: PocketVoice): String =
    voice.id.split('_').joinToString(" ") { part -> part.replaceFirstChar { it.uppercase() } }

@Composable
private fun SettingsScreen(
    state: ReaderState,
    viewModel: ReaderViewModel,
    strings: UiStrings,
    onRequestBatteryOptimization: () -> Unit,
) {
    val uriHandler = LocalUriHandler.current
    var modelLanguage by rememberSaveable { mutableStateOf("") }
    var pendingModelUris by remember { mutableStateOf<List<Uri>?>(null) }
    var confirmClearAll by remember { mutableStateOf(false) }
    val modelPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) pendingModelUris = uris
    }
    val espeakPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { treeUri ->
        val modelUris = pendingModelUris
        if (treeUri != null && modelUris != null) {
            pendingModelUris = null
            viewModel.importCustomModel(modelUris, modelLanguage, treeUri)
        }
    }
    LazyColumn(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Text(strings.settings, style = MaterialTheme.typography.headlineMedium)
            Text(strings.settingsSubtitle)
            state.message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        }
        item {
            Text(strings.interfaceLanguage, style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppLanguage.entries.forEach { language ->
                    Button(onClick = { viewModel.setAppLanguage(language) }, enabled = state.appLanguage != language) { Text(language.label) }
                }
            }
        }
        item {
            Text(strings.systemTheme, style = MaterialTheme.typography.titleMedium)
            Text(strings.systemThemeDescription)
            Spacer(Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ThemeModeButton(
                    label = if (state.appLanguage == AppLanguage.SPANISH) "Sistema" else "System",
                    selected = state.themeMode == AppThemeMode.SYSTEM,
                    onClick = { viewModel.setThemeMode(AppThemeMode.SYSTEM) },
                    modifier = Modifier.weight(1f),
                )
                ThemeModeButton(
                    label = if (state.appLanguage == AppLanguage.SPANISH) "Claro" else "Light",
                    selected = state.themeMode == AppThemeMode.LIGHT,
                    onClick = { viewModel.setThemeMode(AppThemeMode.LIGHT) },
                    modifier = Modifier.weight(1f),
                )
                ThemeModeButton(
                    label = if (state.appLanguage == AppLanguage.SPANISH) "Oscuro" else "Dark",
                    selected = state.themeMode == AppThemeMode.DARK,
                    onClick = { viewModel.setThemeMode(AppThemeMode.DARK) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
        item {
            Text(strings.backgroundPlayback, style = MaterialTheme.typography.titleMedium)
            Text(strings.backgroundPlaybackDescription)
            Spacer(Modifier.height(6.dp))
            Button(onClick = onRequestBatteryOptimization) {
                Text(strings.openBatterySettings)
            }
        }
        item { Text(strings.progressSettings, style = MaterialTheme.typography.titleMedium); Text(strings.progressDescription) }
        item {
            val spanish = state.appLanguage == AppLanguage.SPANISH
            Text(if (spanish) "Privacidad y uso online" else "Privacy and online use", style = MaterialTheme.typography.titleMedium)
            Text(
                if (spanish) {
                    "Los libros, el progreso, los modelos locales y las muestras de voz se guardan en el dispositivo. Edge TTS solo envía a Microsoft los fragmentos que reproduces con una voz Edge."
                } else {
                    "Books, progress, local models, and voice samples remain on this device. Edge TTS only sends Microsoft the fragments you play with an Edge voice."
                },
            )
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = { uriHandler.openUri(PRIVACY_POLICY_URL) }, modifier = Modifier.fillMaxWidth()) {
                Text(if (spanish) "Política de privacidad" else "Privacy policy")
            }
            OutlinedButton(onClick = { uriHandler.openUri(THIRD_PARTY_NOTICES_URL) }, modifier = Modifier.fillMaxWidth()) {
                Text(if (spanish) "Licencias y atribuciones" else "Licenses and attributions")
            }
            OutlinedButton(onClick = { uriHandler.openUri(REPORT_CONTENT_URL) }, modifier = Modifier.fillMaxWidth()) {
                Text(if (spanish) "Informar de audio generado" else "Report synthesized audio")
            }
            Text(
                if (state.edgeConsentGranted) {
                    if (spanish) "Edge TTS online: consentimiento concedido" else "Online Edge TTS: consent granted"
                } else {
                    if (spanish) "Edge TTS online: no autorizado" else "Online Edge TTS: not authorized"
                },
                style = MaterialTheme.typography.bodySmall,
            )
            if (state.edgeConsentGranted) {
                TextButton(onClick = viewModel::revokeEdgeConsent) {
                    Text(if (spanish) "Retirar consentimiento de Edge" else "Revoke Edge consent")
                }
            }
        }
        item {
            Text(strings.importLocalModel, style = MaterialTheme.typography.titleMedium)
            Text(strings.importModelHelp)
            OutlinedTextField(
                value = modelLanguage,
                onValueChange = { modelLanguage = it.lowercase().filter(Char::isLetter).take(3) },
                label = { Text(strings.languageCode) },
                placeholder = { Text("spa") },
                supportingText = { Text("ISO 639-2 · spa, eng, fra…") },
                singleLine = true,
            )
            Spacer(Modifier.height(6.dp))
            Button(onClick = { modelPicker.launch(arrayOf("*/*")) }, enabled = modelLanguage.length == 3) {
                Text(strings.importModel)
            }
        }
        item {
            val spanish = state.appLanguage == AppLanguage.SPANISH
            Text(if (spanish) "Datos locales" else "Local data", style = MaterialTheme.typography.titleMedium)
            Text(
                if (spanish) {
                    "Elimina libros de la biblioteca, progreso, marcadores, modelos, audio generado, portadas, muestras de voz y preferencias. Los documentos originales no se borran."
                } else {
                    "Delete the library, progress, bookmarks, models, generated audio, covers, voice samples, and preferences. Original documents are not deleted."
                },
            )
            Spacer(Modifier.height(6.dp))
            OutlinedButton(
                onClick = { confirmClearAll = true },
                enabled = state.downloading == null && state.downloadQueue.isEmpty() && state.deletingModel == null && !state.clearingLocalData,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    if (state.clearingLocalData) {
                        if (spanish) "Borrando…" else "Deleting…"
                    } else {
                        if (spanish) "Borrar todos los datos locales" else "Delete all local data"
                    },
                )
            }
        }
    }
    if (pendingModelUris != null) {
        AlertDialog(
            onDismissRequest = { pendingModelUris = null },
            title = { Text(if (state.appLanguage == AppLanguage.SPANISH) "espeak-ng-data (opcional)" else "espeak-ng-data (optional)") },
            text = {
                Text(
                    if (state.appLanguage == AppLanguage.SPANISH) {
                        "Algunos modelos Piper necesitan esta carpeta para convertir el texto en fonemas. Puedes seleccionarla ahora o continuar sin ella."
                    } else {
                        "Some Piper models need this folder to convert text to phonemes. You can select it now or continue without it."
                    }
                )
            },
            confirmButton = {
                Button(onClick = { espeakPicker.launch(null) }) {
                    Text(if (state.appLanguage == AppLanguage.SPANISH) "Elegir carpeta" else "Choose folder")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    val modelUris = pendingModelUris
                    pendingModelUris = null
                    if (modelUris != null) viewModel.importCustomModel(modelUris, modelLanguage, null)
                }) {
                    Text(if (state.appLanguage == AppLanguage.SPANISH) "Omitir (opcional)" else "Skip (optional)")
                }
            },
        )
    }
    if (confirmClearAll) {
        val spanish = state.appLanguage == AppLanguage.SPANISH
        AlertDialog(
            onDismissRequest = { confirmClearAll = false },
            title = { Text(if (spanish) "¿Borrar todos los datos locales?" else "Delete all local data?") },
            text = {
                Text(
                    if (spanish) {
                        "Esta acción no se puede deshacer. No elimina los PDF o EPUB originales fuera de la aplicación."
                    } else {
                        "This cannot be undone. PDF or EPUB originals outside the app will not be deleted."
                    },
                )
            },
            confirmButton = {
                Button(onClick = { confirmClearAll = false; viewModel.clearAllLocalData() }) {
                    Text(if (spanish) "Borrar" else "Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmClearAll = false }) {
                    Text(if (spanish) "Cancelar" else "Cancel")
                }
            },
        )
    }
}

@Composable
private fun ThemeModeButton(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (selected) {
        Button(onClick = onClick, modifier = modifier) { Text("✓ $label", maxLines = 1) }
    } else {
        OutlinedButton(onClick = onClick, modifier = modifier) { Text(label, maxLines = 1) }
    }
}

private const val PRIVACY_POLICY_URL = "https://github.com/kroryan/Audiobookreader/blob/main/PRIVACY_POLICY.md"
private const val THIRD_PARTY_NOTICES_URL = "https://github.com/kroryan/Audiobookreader/blob/main/THIRD_PARTY_NOTICES.md"
private const val REPORT_CONTENT_URL = "https://github.com/kroryan/Audiobookreader/issues/new?title=Synthesized%20audio%20report"

private data class UiStrings(
    val library: String, val librarySubtitle: String, val addBook: String, val emptyLibrary: String, val openBook: String,
    val models: String, val modelsSubtitle: String, val settings: String, val settingsSubtitle: String,
    val chapters: String, val voice: String, val savedProgress: String, val fragment: String, val audioReady: String,
    val autoSave: String, val preparing: String, val play: String, val addBookmark: String, val clearAudio: String,
    val clearCache: String, val bookmarks: String, val readingNow: String, val experimental: String, val selected: String,
    val use: String, val downloaded: String, val download: String, val resetProgress: String, val stop: String,
    val previousFragment: String, val nextFragment: String, val tapToPlayFragment: String, val seekPosition: String,
    val voiceSettings: String, val speed: String, val speaker: String, val applyVoiceSettings: String,
    val allLanguages: String, val interfaceLanguage: String, val imported: String,
    val importLocalModel: String, val importModelHelp: String, val languageCode: String, val importModel: String,
    val systemTheme: String, val systemThemeDescription: String, val backgroundPlayback: String, val backgroundPlaybackDescription: String,
    val openBatterySettings: String, val progressSettings: String, val progressDescription: String,
) {
    fun languageLabel(code: String) = if (code == "all") allLanguages else LANGUAGE_NAMES[code] ?: code.uppercase()
    companion object {
        private val LANGUAGE_NAMES = mapOf("af" to "Afrikaans", "ar" to "Arabic", "ca" to "Catalan", "cs" to "Czech", "cy" to "Welsh", "da" to "Danish", "de" to "German", "el" to "Greek", "en" to "English", "es" to "Spanish", "eu" to "Basque", "fa" to "Persian", "fi" to "Finnish", "fr" to "French", "hi" to "Hindi", "hr" to "Croatian", "hu" to "Hungarian", "id" to "Indonesian", "is" to "Icelandic", "it" to "Italian", "ka" to "Georgian", "kk" to "Kazakh", "ku" to "Kurdish", "lb" to "Luxembourgish", "lv" to "Latvian", "ne" to "Nepali", "nl" to "Dutch", "no" to "Norwegian", "pl" to "Polish", "pt" to "Portuguese", "ro" to "Romanian", "ru" to "Russian", "sk" to "Slovak", "sl" to "Slovenian", "sq" to "Albanian", "sr" to "Serbian", "sv" to "Swedish", "sw" to "Swahili", "tr" to "Turkish", "uk" to "Ukrainian", "ur" to "Urdu", "vi" to "Vietnamese", "zh" to "Chinese")
        fun forLanguage(language: AppLanguage) = if (language == AppLanguage.SPANISH) UiStrings("Biblioteca", "Tus libros y su progreso de escucha", "Añadir PDF, EPUB o texto", "Todavía no has añadido ningún libro.", "Abrir libro", "Modelos", "Se descargan bajo demanda y se ejecutan dentro de audiobookreader.", "Ajustes", "Preferencias de la aplicación", "capítulos/páginas", "Voz", "Progreso guardado", "fragmento", "Audio preparado", "La posición se guarda automáticamente cada 20 segundos y al pausar.", "Preparando los primeros minutos…", "Reproducir / continuar", "Guardar marcador", "Limpiar audio", "Limpiar caché", "Marcadores", "leyendo ahora", "Experimental: requiere validación adicional", "Seleccionado", "Usar", "Descargado", "Descargar", "Reiniciar progreso", "Detener", "Fragmento anterior", "Siguiente fragmento", "Toca un fragmento para elegirlo como inicio", "Posición del fragmento", "Configuración de voz", "Velocidad", "ID de voz", "Aplicar configuración", "Todos los idiomas", "Idioma de la interfaz", "Modelo importado", "Importar modelo ONNX", "Selecciona el .onnx y tokens.txt; puedes añadir también el .onnx.json y archivos auxiliares. Se guardan dentro de audiobookreader.", "Código de idioma", "Importar archivos", "Apariencia", "Elige si la aplicación sigue el tema del sistema o utiliza siempre el modo claro u oscuro.", "Reproducción en segundo plano", "Desactiva la optimización de batería para que el TTS y el reproductor sigan funcionando con la pantalla apagada.", "Abrir ajustes de batería", "Guardado de progreso", "El progreso y los marcadores se guardan automáticamente mientras escuchas.") else UiStrings("Library", "Your books and listening progress", "Add PDF, EPUB or text", "You have not added any books yet.", "Open book", "Models", "Downloaded on demand and executed inside audiobookreader.", "Settings", "Application preferences", "chapters/pages", "Voice", "Saved progress", "fragment", "Audio prepared", "Position is saved automatically every 20 seconds and when paused.", "Preparing the first minutes…", "Play / continue", "Save bookmark", "Clear audio", "Clear cache", "Bookmarks", "reading now", "Experimental: requires additional validation", "Selected", "Use", "Downloaded", "Download", "Reset progress", "Stop", "Previous fragment", "Next fragment", "Tap a fragment to choose it as the starting point", "Fragment position", "Voice settings", "Speed", "Voice ID", "Apply settings", "All languages", "Interface language", "Imported model", "Import ONNX model", "Select the .onnx and tokens.txt; you may also add the .onnx.json and auxiliary files. They are stored inside audiobookreader.", "Language code", "Import files", "Appearance", "Choose whether the app follows the system theme or always uses light or dark mode.", "Background playback", "Disable battery optimization so TTS and playback can continue with the screen off.", "Open battery settings", "Progress saving", "Progress and bookmarks are saved automatically while you listen.")
    }
}

private fun formatDuration(milliseconds: Long): String {
    val totalSeconds = (milliseconds / 1000L).coerceAtLeast(0L)
    val hours = totalSeconds / 3600L
    val minutes = (totalSeconds % 3600L) / 60L
    val seconds = totalSeconds % 60L
    return if (hours > 0L) "%d:%02d:%02d".format(hours, minutes, seconds)
    else "%d:%02d".format(minutes, seconds)
}

private fun preferredVoiceLanguage(state: ReaderState): String = when (state.selectedModel.family) {
    ModelFamily.KOKORO -> ModelCatalog.kokoroVoices
        .firstOrNull { it.speakerId == state.bookTtsSettings.speakerId }?.language ?: state.appLanguage.code
    else -> state.selectedModel.language.takeUnless { it == "all" } ?: state.appLanguage.code
}

private fun recentModelRank(state: ReaderState, modelId: String): Int =
    state.recentModelIds.indexOf(modelId).let { if (it < 0) Int.MAX_VALUE else it }

private fun ModelFamily.label() = when (this) {
    ModelFamily.PIPER -> "Piper/VITS"
    ModelFamily.COQUI -> "Coqui/VITS"
    ModelFamily.MIMIC3 -> "Mimic3/VITS"
    ModelFamily.KOKORO -> "Kokoro"
    ModelFamily.KITTEN -> "Kitten"
    ModelFamily.SUPERTONIC -> "Supertonic"
    ModelFamily.POCKET -> "PocketTTS"
    ModelFamily.ZIPVOICE -> "ZipVoice"
    ModelFamily.EDGE -> "Edge TTS"
}
