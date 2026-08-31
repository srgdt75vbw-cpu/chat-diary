import SwiftUI
import PhotosUI
import AuthenticationServices
import CloudKit

// MARK: - 일기 데이터

struct DiaryMessage: Identifiable, Codable {
    let id: UUID
    var text: String
    let date: Date
    var tags: [String]
    var imageData: Data?

    init(
        text: String = "",
        date: Date = Date(),
        tags: [String] = [],
        imageData: Data? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.date = date
        self.tags = tags
        self.imageData = imageData
    }
}

// MARK: - 태그 이동

struct TagSelection: Identifiable {
    let id: String
}

// MARK: - 색상 저장

struct SavedColor {

    static func save(
        _ color: Color,
        key: String
    ) {
        let uiColor = UIColor(color)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        )

        UserDefaults.standard.set(
            [
                Double(red),
                Double(green),
                Double(blue),
                Double(alpha)
            ],
            forKey: key
        )
    }

    static func load(
        key: String,
        defaultColor: Color
    ) -> Color {

        guard let values =
                UserDefaults.standard.array(
                    forKey: key
                ) as? [Double],
              values.count == 4
        else {
            return defaultColor
        }

        return Color(
            red: values[0],
            green: values[1],
            blue: values[2],
            opacity: values[3]
        )
    }
}

// MARK: - CloudKit

final class DiaryCloudManager {

    static let shared =
        DiaryCloudManager()

    private let container =
        CKContainer.default()

    private var database:
        CKDatabase {
        container.privateCloudDatabase
    }

    // 현재 Apple 계정 ID
    var appleUserID: String? {
        UserDefaults.standard.string(
            forKey: "appleUserID"
        )
    }

    // MARK: 메시지 저장

    func saveMessages(
        _ messages: [DiaryMessage]
    ) async {

        guard let userID = appleUserID
        else {
            return
        }

        for message in messages {

            let recordID =
                CKRecord.ID(
                    recordName:
                        "message_\(message.id.uuidString)"
                )

            let record =
                CKRecord(
                    recordType: "DiaryMessage",
                    recordID: recordID
                )

            record["userID"] =
                userID as CKRecordValue

            record["messageID"] =
                message.id.uuidString
                as CKRecordValue

            record["text"] =
                message.text as CKRecordValue

            record["date"] =
                message.date as CKRecordValue

            record["tags"] =
                message.tags as CKRecordValue

            if let imageData =
                message.imageData {

                let url =
                    FileManager.default
                        .temporaryDirectory
                        .appendingPathComponent(
                            "\(message.id.uuidString).jpg"
                        )

                do {

                    try imageData.write(
                        to: url
                    )

                    record["image"] =
                        CKAsset(
                            fileURL: url
                        )

                } catch {
                    print(
                        "사진 저장 실패:",
                        error
                    )
                }
            }

            do {

                try await database.save(
                    record
                )

            } catch {

                print(
                    "CloudKit 저장 실패:",
                    error
                )
            }
        }
    }

    // MARK: 메시지 불러오기

    func loadMessages()
        async -> [DiaryMessage]? {

        guard let userID = appleUserID
        else {
            return nil
        }

        let predicate =
            NSPredicate(
                format:
                    "userID == %@",
                userID
            )

        let query =
            CKQuery(
                recordType:
                    "DiaryMessage",
                predicate:
                    predicate
            )

        do {

            let result =
                try await database.records(
                    matching: query
                )

            var loaded:
                [DiaryMessage] = []

            for (_, recordResult)
                in result.matchResults {

                guard
                    let record =
                        try? recordResult.get()
                else {
                    continue
                }

                let idString =
                    record["messageID"]
                    as? String

                guard
                    let idString,
                    let uuid =
                        UUID(
                            uuidString:
                                idString
                        )
                else {
                    continue
                }

                let text =
                    record["text"]
                    as? String ?? ""

                let date =
                    record["date"]
                    as? Date ?? Date()

                let tags =
                    record["tags"]
                    as? [String] ?? []

                var imageData:
                    Data?

                if let asset =
                    record["image"]
                    as? CKAsset,
                   let url =
                    asset.fileURL {

                    imageData =
                        try? Data(
                            contentsOf: url
                        )
                }

                let message =
                    DiaryMessage(
                        text: text,
                        date: date,
                        tags: tags,
                        imageData:
                            imageData
                    )

                // UUID 유지
                let fixed =
                    DiaryMessage(
                        id: uuid,
                        text: message.text,
                        date: message.date,
                        tags: message.tags,
                        imageData:
                            message.imageData
                    )

                loaded.append(fixed)
            }

            return loaded.sorted {
                $0.date < $1.date
            }

        } catch {

            print(
                "CloudKit 불러오기 실패:",
                error
            )

            return nil
        }
    }

    // MARK: 삭제

    func deleteMessage(
        _ message: DiaryMessage
    ) async {

        let recordID =
            CKRecord.ID(
                recordName:
                    "message_\(message.id.uuidString)"
            )

        do {

            try await database.deleteRecord(
                withID: recordID
            )

        } catch {

            print(
                "CloudKit 삭제 실패:",
                error
            )
        }
    }
}

// MARK: - 메인

struct ContentView: View {

    @State private var messages:
        [DiaryMessage] =
        DiaryStorage.loadMessages()

    @State private var tags:
        [String] =
        DiaryStorage.loadTags()

    @State private var inputText =
        ""

    @State private var selectedMessage:
        DiaryMessage?

    @State private var selectedTag:
        TagSelection?

    @State private var backgroundColor:
        Color =
        SavedColor.load(
            key: "backgroundColor",
            defaultColor: .white
        )

    @State private var bubbleColor:
        Color =
        SavedColor.load(
            key: "bubbleColor",
            defaultColor: .black
        )

    @State private var backgroundImageData:
        Data? =
        UserDefaults.standard.data(
            forKey: "backgroundImage"
        )

    @State private var backgroundScale:
        CGFloat =
        UserDefaults.standard.object(
            forKey: "backgroundScale"
        ) as? CGFloat ?? 1.0

    @State private var backgroundOffsetX:
        CGFloat =
        UserDefaults.standard.object(
            forKey: "backgroundOffsetX"
        ) as? CGFloat ?? 0

    @State private var backgroundOffsetY:
        CGFloat =
        UserDefaults.standard.object(
            forKey: "backgroundOffsetY"
        ) as? CGFloat ?? 0

    var body: some View {

        TabView {

            // MARK: Diary

            DiaryView(
                messages:
                    $messages,
                inputText:
                    $inputText,
                selectedMessage:
                    $selectedMessage,
                backgroundColor:
                    $backgroundColor,
                bubbleColor:
                    $bubbleColor,
                backgroundImageData:
                    $backgroundImageData,
                backgroundScale:
                    $backgroundScale,
                backgroundOffsetX:
                    $backgroundOffsetX,
                backgroundOffsetY:
                    $backgroundOffsetY
            )
            .tabItem {

                Image(
                    systemName:
                        "book"
                )

                Text("Diary")
            }

            // MARK: Tags

            TagListView(
                messages:
                    messages,
                tags:
                    $tags,
                selectedTag:
                    $selectedTag
            )
            .tabItem {

                Image(
                    systemName:
                        "number"
                )

                Text("Tags")
            }

            // MARK: Settings

            SettingsView(
                backgroundColor:
                    $backgroundColor,
                bubbleColor:
                    $bubbleColor,
                backgroundImageData:
                    $backgroundImageData,
                backgroundScale:
                    $backgroundScale,
                backgroundOffsetX:
                    $backgroundOffsetX,
                backgroundOffsetY:
                    $backgroundOffsetY
            )
            .tabItem {

                Image(
                    systemName:
                        "gearshape"
                )

                Text("Settings")
            }
        }

        .sheet(
            item:
                $selectedMessage
        ) { message in

            TagSheet(
                message:
                    message,
                allTags:
                    $tags
            ) { newTags in

                updateTags(
                    for:
                        message,
                    tags:
                        newTags
                )
            }
        }

        .sheet(
            item:
                $selectedTag
        ) { selection in

            TaggedDiaryView(
                tag:
                    selection.id,
                messages:
                    messages
            )
        }
    }

    private func updateTags(
        for message:
            DiaryMessage,
        tags:
            [String]
    ) {

        guard let index =
                messages.firstIndex(
                    where: {
                        $0.id ==
                        message.id
                    }
                )
        else {
            return
        }

        messages[index].tags =
            tags

        DiaryStorage.saveMessages(
            messages
        )

        Task {

            await DiaryCloudManager
                .shared
                .saveMessages(
                    messages
                )
        }
    }
}

// MARK: - Diary

struct DiaryView: View {

    @Binding var messages:
        [DiaryMessage]

    @Binding var inputText:
        String

    @Binding var selectedMessage:
        DiaryMessage?

    @Binding var backgroundColor:
        Color

    @Binding var bubbleColor:
        Color

    @Binding var backgroundImageData:
        Data?

    @Binding var backgroundScale:
        CGFloat

    @Binding var backgroundOffsetX:
        CGFloat

    @Binding var backgroundOffsetY:
        CGFloat

    @State private var editingMessage:
        DiaryMessage?

    @State private var searchText =
        ""

    @State private var photoItem:
        PhotosPickerItem?

    @FocusState private var inputFocused:
        Bool

    var filteredMessages:
        [DiaryMessage] {

        if searchText
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .isEmpty {

            return messages
        }

        return messages.filter {

            $0.text
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }

    var body: some View {

        NavigationStack {

            ZStack {

                // MARK: 배경

                GeometryReader { geo in

                    if let data =
                        backgroundImageData,
                       let image =
                        UIImage(
                            data:
                                data
                        ) {

                        Image(
                            uiImage:
                                image
                        )
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(
                            backgroundScale
                        )
                        .offset(
                            x:
                                backgroundOffsetX,
                            y:
                                backgroundOffsetY
                        )
                        .frame(
                            width:
                                geo.size.width,
                            height:
                                geo.size.height
                        )
                        .clipped()
                        .ignoresSafeArea()

                    } else {

                        backgroundColor
                            .ignoresSafeArea()
                    }
                }

                // MARK: 내용

                VStack(
                    spacing: 0
                ) {

                    // 검색

                    HStack(
                        spacing: 10
                    ) {

                        Image(
                            systemName:
                                "magnifyingglass"
                        )
                        .foregroundStyle(
                            .secondary
                        )

                        TextField(
                            "일기 검색",
                            text:
                                $searchText
                        )
                        .textFieldStyle(
                            .plain
                        )
                    }
                    .padding(
                        .horizontal,
                        14
                    )
                    .padding(
                        .vertical,
                        11
                    )
                    .background(
                        Color(
                            red:
                                0.92,
                            green:
                                0.92,
                            blue:
                                0.94
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:
                                20
                        )
                    )
                    .padding(
                        .horizontal
                    )
                    .padding(
                        .vertical,
                        8
                    )

                    // MARK: 일기

                    ScrollViewReader {
                        proxy in

                        ScrollView {

                            LazyVStack(
                                spacing:
                                    12
                            ) {

                                ForEach(
                                    Array(
                                        filteredMessages
                                            .enumerated()
                                    ),
                                    id:
                                        \.element.id
                                ) {
                                    index,
                                    message in

                                    if shouldShowDate(
                                        for:
                                            index
                                    ) {

                                        dateDivider(
                                            for:
                                                message.date
                                        )
                                    }

                                    messageBubble(
                                        message:
                                            message
                                    )
                                    .id(
                                        message.id
                                    )
                                }
                            }
                            .padding()
                        }
                        .scrollDismissesKeyboard(
                            .interactively
                        )
                        .onChange(
                            of:
                                messages.count
                        ) {

                            if let last =
                                messages.last {

                                withAnimation {

                                    proxy.scrollTo(
                                        last.id,
                                        anchor:
                                            .bottom
                                    )
                                }
                            }
                        }
                    }

                    Divider()

                    // MARK: 입력

                    HStack(
                        alignment:
                            .bottom,
                        spacing:
                            8
                    ) {

                        // 사진 버튼

                        PhotosPicker(
                            selection:
                                $photoItem,
                            matching:
                                .images
                        ) {

                            Image(
                                systemName:
                                    "photo"
                            )
                            .font(
                                .system(
                                    size:
                                        22
                                )
                            )
                            .foregroundStyle(
                                .primary
                            )
                        }

                        TextField(
                            "오늘의 이야기를 적어보세요",
                            text:
                                $inputText,
                            axis:
                                .vertical
                        )
                        .textFieldStyle(
                            .plain
                        )
                        .focused(
                            $inputFocused
                        )
                        .padding(
                            .horizontal,
                            14
                        )
                        .padding(
                            .vertical,
                            10
                        )
                        .background(
                            Color(
                                red:
                                    0.92,
                                green:
                                    0.92,
                                blue:
                                    0.94
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius:
                                    20
                            )
                        )

                        Button {

                            sendMessage()

                        } label: {

                            Image(
                                systemName:
                                    "arrow.up.circle.fill"
                            )
                            .font(
                                .system(
                                    size:
                                        30
                                )
                            )
                        }
                        .disabled(
                            inputText
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                    }
                    .padding(
                        .horizontal
                    )
                    .padding(
                        .vertical,
                        8
                    )
                }
            }

            .navigationTitle(
                "Diary"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
        }

        // MARK: 사진 선택

        .onChange(
            of:
                photoItem
        ) { _, newItem in

            Task {

                guard
                    let data =
                        try? await newItem?
                            .loadTransferable(
                                type:
                                    Data.self
                            )
                else {
                    return
                }

                sendPhoto(
                    data
                )

                photoItem = nil
            }
        }

        // MARK: 수정

        .sheet(
            item:
                $editingMessage
        ) { message in

            EditDiaryView(
                message:
                    message
            ) { newText in

                updateMessage(
                    message,
                    newText:
                        newText
                )
            }
        }
    }

    // MARK: 메시지 UI

    @ViewBuilder
    private func messageBubble(
        message:
            DiaryMessage
    ) -> some View {

        VStack(
            alignment:
                .trailing,
            spacing:
                4
        ) {

            if let data =
                message.imageData,
               let image =
                UIImage(
                    data:
                        data
                ) {

                Image(
                    uiImage:
                        image
                )
                .resizable()
                .scaledToFit()
                .frame(
                    maxWidth:
                        240,
                    maxHeight:
                        320
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            18
                    )
                )
                .contextMenu {

                    messageMenu(
                        message
                    )
                }
            }

            if !message.text.isEmpty {

                Text(
                    message.text
                )
                .font(
                    .system(
                        size:
                            16
                    )
                )
                .foregroundStyle(
                    .white
                )
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .vertical,
                    10
                )
                .background(
                    bubbleColor
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            18
                    )
                )
                .contextMenu {

                    messageMenu(
                        message
                    )
                }
            }

            if !message.tags.isEmpty {

                HStack(
                    spacing:
                        5
                ) {

                    ForEach(
                        message.tags,
                        id:
                            \.self
                    ) { tag in

                        Text(
                            "#\(tag)"
                        )
                        .font(
                            .system(
                                size:
                                    11
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }

            Text(
                message.date,
                style:
                    .time
            )
            .font(
                .system(
                    size:
                        11
                )
            )
            .foregroundStyle(
                .secondary
            )
        }
        .frame(
            maxWidth:
                .infinity,
            alignment:
                .trailing
        )
    }

    @ViewBuilder
    private func messageMenu(
        _ message:
            DiaryMessage
    ) -> some View {

        Button {

            editingMessage =
                message

        } label: {

            Label(
                "수정",
                systemImage:
                    "pencil"
            )
        }

        Button {

            selectedMessage =
                message

        } label: {

            Label(
                "태그 설정",
                systemImage:
                    "tag"
            )
        }

        Button(
            role:
                .destructive
        ) {

            deleteMessage(
                message
            )

        } label: {

            Label(
                "삭제",
                systemImage:
                    "trash"
            )
        }
    }

    // MARK: 글 보내기

    private func sendMessage() {

        let text =
            inputText
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !text.isEmpty
        else {
            return
        }

        let message =
            DiaryMessage(
                text:
                    text
            )

        messages.append(
            message
        )

        DiaryStorage.saveMessages(
            messages
        )

        Task {

            await DiaryCloudManager
                .shared
                .saveMessages(
                    messages
                )
        }

        inputText = ""

        // 키보드 내리기
        inputFocused = false
    }

    // MARK: 사진 보내기

    private func sendPhoto(
        _ data:
            Data
    ) {

        let message =
            DiaryMessage(
                imageData:
                    data
            )

        messages.append(
            message
        )

        DiaryStorage.saveMessages(
            messages
        )

        Task {

            await DiaryCloudManager
                .shared
                .saveMessages(
                    messages
                )
        }

        inputFocused = false
    }

    // MARK: 수정

    private func updateMessage(
        _ message:
            DiaryMessage,
        newText:
            String
    ) {

        guard let index =
                messages.firstIndex(
                    where: {
                        $0.id ==
                        message.id
                    }
                )
        else {
            return
        }

        messages[index].text =
            newText

        DiaryStorage.saveMessages(
            messages
        )

        Task {

            await DiaryCloudManager
                .shared
                .saveMessages(
                    messages
                )
        }
    }

    // MARK: 삭제

    private func deleteMessage(
        _ message:
            DiaryMessage
    ) {

        messages.removeAll {
            $0.id ==
            message.id
        }

        DiaryStorage.saveMessages(
            messages
        )

        Task {

            await DiaryCloudManager
                .shared
                .deleteMessage(
                    message
                )
        }
    }

    // MARK: 날짜

    private func shouldShowDate(
        for index:
            Int
    ) -> Bool {

        if index == 0 {
            return true
        }

        return !Calendar.current
            .isDate(
                filteredMessages[
                    index - 1
                ].date,
                inSameDayAs:
                    filteredMessages[
                        index
                    ].date
            )
    }

    private func dateDivider(
        for date:
            Date
    ) -> some View {

        HStack(
            spacing:
                10
        ) {

            Rectangle()
                .frame(
                    height:
                        0.7
                )

            Text(
                String(
                    format:
                        "%04d.%02d.%02d",
                    Calendar.current
                        .component(
                            .year,
                            from:
                                date
                        ),
                    Calendar.current
                        .component(
                            .month,
                            from:
                                date
                        ),
                    Calendar.current
                        .component(
                            .day,
                            from:
                                date
                        )
                )
            )
            .font(
                .system(
                    size:
                        12,
                    weight:
                        .medium
                )
            )
            .padding(
                .horizontal,
                9
            )
            .padding(
                .vertical,
                5
            )
            .background(
                .ultraThinMaterial
            )
            .clipShape(
                Capsule()
            )

            Rectangle()
                .frame(
                    height:
                        0.7
                )
        }
        .foregroundStyle(
            .secondary
        )
        .padding(
            .vertical,
            12
        )
    }
}

// MARK: - 태그 목록

struct TagListView: View {

    let messages:
        [DiaryMessage]

    @Binding var tags:
        [String]

    @Binding var selectedTag:
        TagSelection?

    @State private var newTag =
        ""

    var body: some View {

        NavigationStack {

            List {

                Section {

                    if tags.isEmpty {

                        Text(
                            "아직 만든 태그가 없어요"
                        )
                        .foregroundStyle(
                            .secondary
                        )

                    } else {

                        ForEach(
                            tags,
                            id:
                                \.self
                        ) { tag in

                            Button {

                                selectedTag =
                                    TagSelection(
                                        id:
                                            tag
                                    )

                            } label: {

                                HStack {

                                    Text(
                                        "#\(tag)"
                                    )
                                    .foregroundStyle(
                                        .primary
                                    )

                                    Spacer()

                                    Text(
                                        "\(messages.filter { $0.tags.contains(tag) }.count)"
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(
                                        .caption
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                        }
                        .onDelete {
                            indexSet in

                            tags.remove(
                                atOffsets:
                                    indexSet
                            )

                            DiaryStorage.saveTags(
                                tags
                            )
                        }
                    }

                } header: {

                    Text(
                        "MY TAGS"
                    )
                }

                Section(
                    "새 태그"
                ) {

                    HStack {

                        TextField(
                            "예: 영화",
                            text:
                                $newTag
                        )

                        Button(
                            "추가"
                        ) {
                            addTag()
                        }
                    }
                }
            }

            .navigationTitle(
                "Tags"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
        }
    }

    private func addTag() {

        let cleaned =
            newTag
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !cleaned.isEmpty
        else {
            return
        }

        guard !tags.contains(
            cleaned
        )
        else {
            return
        }

        tags.append(
            cleaned
        )

        DiaryStorage.saveTags(
            tags
        )

        newTag = ""
    }
}

// MARK: - 태그별 일기

struct TaggedDiaryView: View {

    let tag:
        String

    let messages:
        [DiaryMessage]

    @Environment(\.dismiss)
    private var dismiss

    @State private var searchText =
        ""

    private var filteredMessages:
        [DiaryMessage] {

        messages.filter {

            $0.tags.contains(
                tag
            )
            &&
            (
                searchText.isEmpty
                ||
                $0.text
                    .localizedCaseInsensitiveContains(
                        searchText
                    )
            )
        }
    }

    var body: some View {

        NavigationStack {

            List {

                ForEach(
                    filteredMessages
                ) { message in

                    VStack(
                        alignment:
                            .leading,
                        spacing:
                            6
                    ) {

                        if let data =
                            message.imageData,
                           let image =
                            UIImage(
                                data:
                                    data
                            ) {

                            Image(
                                uiImage:
                                    image
                            )
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxHeight:
                                    200
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius:
                                        12
                                )
                            )
                        }

                        if !message.text.isEmpty {

                            Text(
                                message.text
                            )
                        }

                        Text(
                            message.date,
                            format:
                                .dateTime
                                .year()
                                .month()
                                .day()
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .padding(
                        .vertical,
                        4
                    )
                }
            }
            .searchable(
                text:
                    $searchText,
                prompt:
                    "이 태그의 일기 검색"
            )
            .navigationTitle(
                "#\(tag)"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {

                    Button(
                        "닫기"
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 태그 설정

struct TagSheet: View {

    let message:
        DiaryMessage

    @Binding var allTags:
        [String]

    let onSave:
        ([String]) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedTags:
        Set<String>

    @State private var newTag =
        ""

    init(
        message:
            DiaryMessage,
        allTags:
            Binding<[String]>,
        onSave:
            @escaping (
                [String]
            ) -> Void
    ) {

        self.message =
            message

        self._allTags =
            allTags

        self.onSave =
            onSave

        self._selectedTags =
            State(
                initialValue:
                    Set(
                        message.tags
                    )
            )
    }

    var body: some View {

        NavigationStack {

            List {

                Section(
                    "일기"
                ) {

                    Text(
                        message.text.isEmpty
                        ? "사진"
                        : message.text
                    )
                }

                Section(
                    "태그"
                ) {

                    ForEach(
                        allTags,
                        id:
                            \.self
                    ) { tag in

                        Button {

                            if selectedTags
                                .contains(
                                    tag
                                ) {

                                selectedTags
                                    .remove(
                                        tag
                                    )

                            } else {

                                selectedTags
                                    .insert(
                                        tag
                                    )
                            }

                        } label: {

                            HStack {

                                Text(
                                    "#\(tag)"
                                )
                                .foregroundStyle(
                                    .primary
                                )

                                Spacer()

                                if selectedTags
                                    .contains(
                                        tag
                                    ) {

                                    Image(
                                        systemName:
                                            "checkmark"
                                    )
                                    .foregroundStyle(
                                        .blue
                                    )
                                }
                            }
                        }
                    }
                }

                Section(
                    "새 태그 만들기"
                ) {

                    HStack {

                        TextField(
                            "예: 운동",
                            text:
                                $newTag
                        )

                        Button(
                            "추가"
                        ) {
                            addNewTag()
                        }
                    }
                }
            }

            .navigationTitle(
                "태그 설정"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {

                    Button(
                        "완료"
                    ) {

                        onSave(
                            Array(
                                selectedTags
                            )
                        )

                        dismiss()
                    }
                }
            }
        }
    }

    private func addNewTag() {

        let cleaned =
            newTag
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !cleaned.isEmpty
        else {
            return
        }

        if !allTags.contains(
            cleaned
        ) {

            allTags.append(
                cleaned
            )

            DiaryStorage.saveTags(
                allTags
            )
        }

        selectedTags.insert(
            cleaned
        )

        newTag = ""
    }
}

// MARK: - 설정

struct SettingsView: View {

    @Binding var backgroundColor:
        Color

    @Binding var bubbleColor:
        Color

    @Binding var backgroundImageData:
        Data?

    @Binding var backgroundScale:
        CGFloat

    @Binding var backgroundOffsetX:
        CGFloat

    @Binding var backgroundOffsetY:
        CGFloat

    var body: some View {

        NavigationStack {

            List {

                Section {

                    NavigationLink {

                        AppleLoginView()

                    } label: {

                        HStack(
                            spacing:
                                14
                        ) {

                            Image(
                                systemName:
                                    "apple.logo"
                            )
                            .font(
                                .system(
                                    size:
                                        20
                                )
                            )

                            Text(
                                "Login"
                            )

                            Spacer()
                        }
                    }

                    NavigationLink {

                        DisplaySettingsView(
                            backgroundColor:
                                $backgroundColor,
                            bubbleColor:
                                $bubbleColor,
                            backgroundImageData:
                                $backgroundImageData,
                            backgroundScale:
                                $backgroundScale,
                            backgroundOffsetX:
                                $backgroundOffsetX,
                            backgroundOffsetY:
                                $backgroundOffsetY
                        )

                    } label: {

                        HStack(
                            spacing:
                                14
                        ) {

                            Image(
                                systemName:
                                    "paintpalette"
                            )

                            Text(
                                "Display"
                            )
                        }
                    }
                }
            }

            .navigationTitle(
                "Settings"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
        }
    }
}

// MARK: - 디스플레이 설정

struct DisplaySettingsView: View {

    @Binding var backgroundColor:
        Color

    @Binding var bubbleColor:
        Color

    @Binding var backgroundImageData:
        Data?

    @Binding var backgroundScale:
        CGFloat

    @Binding var backgroundOffsetX:
        CGFloat

    @Binding var backgroundOffsetY:
        CGFloat

    @State private var photoItem:
        PhotosPickerItem?

    @State private var showingCrop =
        false

    var body: some View {

        List {

            Section(
                "Background"
            ) {

                ColorPicker(
                    "Background Color",
                    selection:
                        $backgroundColor,
                    supportsOpacity:
                        false
                )
                .onChange(
                    of:
                        backgroundColor
                ) {

                    SavedColor.save(
                        backgroundColor,
                        key:
                            "backgroundColor"
                    )
                }

                PhotosPicker(
                    selection:
                        $photoItem,
                    matching:
                        .images
                ) {

                    HStack {

                        Text(
                            "Background Photo"
                        )

                        Spacer()

                        Image(
                            systemName:
                                "photo"
                        )
                    }
                }

                if backgroundImageData != nil {

                    Button(
                        "사진 위치 / 크기 조정"
                    ) {

                        showingCrop =
                            true
                    }

                    Button(
                        "사진 제거",
                        role:
                            .destructive
                    ) {

                        backgroundImageData =
                            nil

                        UserDefaults.standard
                            .removeObject(
                                forKey:
                                    "backgroundImage"
                            )
                    }
                }
            }

            Section(
                "Bubble"
            ) {

                ColorPicker(
                    "Bubble Color",
                    selection:
                        $bubbleColor,
                    supportsOpacity:
                        false
                )
                .onChange(
                    of:
                        bubbleColor
                ) {

                    SavedColor.save(
                        bubbleColor,
                        key:
                            "bubbleColor"
                    )
                }
            }
        }

        .navigationTitle(
            "Display"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )

        .onChange(
            of:
                photoItem
        ) { _, newItem in

            Task {

                guard let data =
                        try? await newItem?
                            .loadTransferable(
                                type:
                                    Data.self
                            )
                else {
                    return
                }

                backgroundImageData =
                    data

                backgroundScale =
                    1.0

                backgroundOffsetX =
                    0

                backgroundOffsetY =
                    0

                UserDefaults.standard.set(
                    data,
                    forKey:
                        "backgroundImage"
                )

                savePosition()
            }
        }

        .sheet(
            isPresented:
                $showingCrop
        ) {

            BackgroundCropView(
                imageData:
                    backgroundImageData,
                scale:
                    $backgroundScale,
                offsetX:
                    $backgroundOffsetX,
                offsetY:
                    $backgroundOffsetY
            )
        }
    }

    private func savePosition() {

        UserDefaults.standard.set(
            backgroundScale,
            forKey:
                "backgroundScale"
        )

        UserDefaults.standard.set(
            backgroundOffsetX,
            forKey:
                "backgroundOffsetX"
        )

        UserDefaults.standard.set(
            backgroundOffsetY,
            forKey:
                "backgroundOffsetY"
        )
    }
}

// MARK: - 배경 사진 조정

struct BackgroundCropView: View {

    let imageData:
        Data?

    @Binding var scale:
        CGFloat

    @Binding var offsetX:
        CGFloat

    @Binding var offsetY:
        CGFloat

    @Environment(\.dismiss)
    private var dismiss

    @State private var currentScale:
        CGFloat = 1

    @State private var currentX:
        CGFloat = 0

    @State private var currentY:
        CGFloat = 0

    @State private var lastScale:
        CGFloat = 1

    @State private var lastX:
        CGFloat = 0

    @State private var lastY:
        CGFloat = 0

    var body: some View {

        NavigationStack {

            GeometryReader { geo in

                ZStack {

                    Color.black
                        .ignoresSafeArea()

                    if let data =
                        imageData,
                       let image =
                        UIImage(
                            data:
                                data
                        ) {

                        Image(
                            uiImage:
                                image
                        )
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(
                            currentScale
                        )
                        .offset(
                            x:
                                currentX,
                            y:
                                currentY
                        )
                        .frame(
                            width:
                                geo.size.width,
                            height:
                                geo.size.height
                        )
                        .clipped()
                        .gesture(

                            DragGesture()
                                .onChanged {
                                    value in

                                    currentX =
                                        lastX
                                        +
                                        value
                                            .translation
                                            .width

                                    currentY =
                                        lastY
                                        +
                                        value
                                            .translation
                                            .height
                                }
                                .onEnded { _ in

                                    lastX =
                                        currentX

                                    lastY =
                                        currentY

                                    save()
                                }
                        )
                        .simultaneousGesture(

                            MagnificationGesture()
                                .onChanged {
                                    value in

                                    currentScale =
                                        max(
                                            1,
                                            min(
                                                5,
                                                lastScale
                                                * value
                                            )
                                        )
                                }
                                .onEnded { _ in

                                    lastScale =
                                        currentScale

                                    save()
                                }
                        )
                    }

                    VStack {

                        Spacer()

                        Text(
                            "드래그해서 이동 · 두 손가락으로 확대/축소"
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .white
                        )
                        .padding(
                            .horizontal,
                            14
                        )
                        .padding(
                            .vertical,
                            8
                        )
                        .background(
                            .ultraThinMaterial
                        )
                        .clipShape(
                            Capsule()
                        )
                        .padding(
                            .bottom,
                            20
                        )
                    }
                }
            }

            .navigationTitle(
                "배경 조정"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {

                    Button(
                        "완료"
                    ) {

                        save()
                        dismiss()
                    }
                }
            }

            .onAppear {

                currentScale =
                    scale

                currentX =
                    offsetX

                currentY =
                    offsetY

                lastScale =
                    scale

                lastX =
                    offsetX

                lastY =
                    offsetY
            }
        }
    }

    private func save() {

        scale =
            currentScale

        offsetX =
            currentX

        offsetY =
            currentY

        UserDefaults.standard.set(
            currentScale,
            forKey:
                "backgroundScale"
        )

        UserDefaults.standard.set(
            currentX,
            forKey:
                "backgroundOffsetX"
        )

        UserDefaults.standard.set(
            currentY,
            forKey:
                "backgroundOffsetY"
        )
    }
}

// MARK: - Apple 로그인

struct AppleLoginView: View {

    @State private var isLoggedIn =
        false

    @State private var loginError =
        ""

    var body: some View {

        VStack(
            spacing:
                25
        ) {

            Image(
                systemName:
                    "apple.logo"
            )
            .font(
                .system(
                    size:
                        60
                )
            )

            Text(
                isLoggedIn
                ? "Logged In"
                : "Login"
            )
            .font(
                .title2.bold()
            )

            if isLoggedIn {

                Text(
                    "이 계정의 일기를 불러오는 중..."
                )
                .foregroundStyle(
                    .secondary
                )

            } else {

                Text(
                    "Apple 계정으로 로그인하세요."
                )
                .foregroundStyle(
                    .secondary
                )

                SignInWithAppleButton(
                    .signIn,
                    onRequest: {
                        request in

                        request
                            .requestedScopes =
                            [
                                .fullName,
                                .email
                            ]
                    },
                    onCompletion: {
                        result in

                        handleLogin(
                            result
                        )
                    }
                )
                .signInWithAppleButtonStyle(
                    .black
                )
                .frame(
                    height:
                        50
                )
                .padding(
                    .horizontal,
                    30
                )
            }

            if !loginError.isEmpty {

                Text(
                    loginError
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .red
                )
            }

            Spacer()
        }
        .padding(
            .top,
            50
        )
        .navigationTitle(
            "Login"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .onAppear {

            isLoggedIn =
                UserDefaults.standard
                    .string(
                        forKey:
                            "appleUserID"
                    ) != nil
        }
    }

    private func handleLogin(
        _ result:
            Result<
                ASAuthorization,
                Error
            >
    ) {

        switch result {

        case .success(
            let authorization
        ):

            guard let credential =
                    authorization
                        .credential
                        as? ASAuthorizationAppleIDCredential
            else {
                return
            }

            let userID =
                credential.user

            UserDefaults.standard.set(
                userID,
                forKey:
                    "appleUserID"
            )

            isLoggedIn =
                true

            // 로그인한 계정의 기존 일기 불러오기
            Task {

                if let cloudMessages =
                    await DiaryCloudManager
                        .shared
                        .loadMessages() {

                    if !cloudMessages.isEmpty {

                        await MainActor.run {

                            DiaryStorage
                                .saveMessages(
                                    cloudMessages
                                )
                        }
                    }
                }
            }

        case .failure(let error):

            loginError =
                error.localizedDescription
        }
    }
}

// MARK: - 일기 수정

struct EditDiaryView: View {

    let message:
        DiaryMessage

    let onSave:
        (String) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var newText:
        String

    init(
        message:
            DiaryMessage,
        onSave:
            @escaping (
                String
            ) -> Void
    ) {

        self.message =
            message

        self.onSave =
            onSave

        _newText =
            State(
                initialValue:
                    message.text
            )
    }

    var body: some View {

        NavigationStack {

            TextEditor(
                text:
                    $newText
            )
            .padding()
            .navigationTitle(
                "일기 수정"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {

                    Button(
                        "저장"
                    ) {

                        onSave(
                            newText
                        )

                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 저장

struct DiaryStorage {

    private static let messageKey =
        "saved_diary_messages"

    private static let tagKey =
        "saved_diary_tags"

    static func saveMessages(
        _ messages:
            [DiaryMessage]
    ) {

        if let data =
            try? JSONEncoder()
                .encode(
                    messages
                ) {

            UserDefaults.standard.set(
                data,
                forKey:
                    messageKey
            )
        }
    }

    static func loadMessages()
        -> [DiaryMessage] {

        guard let data =
                UserDefaults.standard
                    .data(
                        forKey:
                            messageKey
                    )
        else {
            return []
        }

        return (
            try? JSONDecoder()
                .decode(
                    [
                        DiaryMessage
                    ].self,
                    from:
                        data
                )
        ) ?? []
    }

    static func saveTags(
        _ tags:
            [String]
    ) {

        UserDefaults.standard.set(
            tags,
            forKey:
                tagKey
        )
    }

    static func loadTags()
        -> [String] {

        UserDefaults.standard
            .stringArray(
                forKey:
                    tagKey
            ) ?? []
    }
}

// MARK: - CloudKit용 UUID initializer

extension DiaryMessage {

    init(
        id:
            UUID,
        text:
            String,
        date:
            Date,
        tags:
            [String],
        imageData:
            Data?
    ) {

        self.id =
            id

        self.text =
            text

        self.date =
            date

        self.tags =
            tags

        self.imageData =
            imageData
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
