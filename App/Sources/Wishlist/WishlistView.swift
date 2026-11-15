import PhotosUI
import PlannerCore
import SwiftUI
import UIKit

/// The wishlist ("Λίστα επιθυμιών"), from the heart on the To Buy page: square pictures,
/// newest first, and a + that opens the system's photo picker (several photos at once).
/// The picker needs no permission: the app sees only the photos she picks, and copies
/// them. Tap a photo for the whole screen; hold one to delete it. Photos keep their
/// colours; everything around them is black and white.
struct WishlistView: View {
    let book: WishlistBook

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: WishlistPhoto?
    @State private var pendingDelete: WishlistPhoto?

    var body: some View {
        let photos = book.photos
        NavigationStack {
            ScrollView {
                if photos.isEmpty && book.adding == 0 {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(0..<book.adding, id: \.self) { _ in
                            addingCell
                        }
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            cell(photo, number: index + 1)
                        }
                    }
                    .padding(spacing)
                }
            }
            .background(Paper.fill)
            .navigationTitle(Text("Wishlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    picker {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .accessibilityLabel(Text("Add photos"))
                    .accessibilityIdentifier("wishlist.add")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("wishlist.done")
                }
            }
            .confirmationDialog(
                Text("Delete this photo?"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { photo in
                Button {
                    book.delete(photo.id)
                } label: {
                    Text("Delete")
                }
                .accessibilityIdentifier("wishlist.confirmDelete")
                Button(role: .cancel) {
                } label: {
                    Text("Cancel")
                }
            } message: { _ in
                Text("It is deleted from the app only, not from your photo library.")
            }
        }
        .tint(Paper.ink)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task {
                await book.add(items)
            }
        }
        .fullScreenCover(item: $viewing) { photo in
            WishlistPhotoViewer(book: book, start: photo.id)
        }
        .alert(
            Text("Some photos could not be added."),
            isPresented: Binding(get: { book.failedToAdd > 0 && book.adding == 0 }, set: { if !$0 { book.failedToAdd = 0 } })
        ) {
            Button {
            } label: {
                Text("OK")
            }
        }
    }

    // MARK: - Parts

    private var compact: Bool { sizeClass == .compact }
    private var spacing: CGFloat { compact ? 4 : 8 }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: compact ? 104 : 170, maximum: 260), spacing: spacing)]
    }

    /// The system's photo picker: images only, several at once, the original files.
    private func picker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(
            selection: $picked, maxSelectionCount: 50, selectionBehavior: .ordered,
            matching: .images, preferredItemEncoding: .current, label: label
        )
    }

    /// A big + and one line of text.
    private var emptyState: some View {
        VStack(spacing: 18) {
            picker {
                Image(systemName: "plus")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 128, height: 128)
                    .background(Paper.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Paper.ink, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Add photos"))
            .accessibilityIdentifier("wishlist.empty.add")
            Text("Add photos of things you'd like to buy.")
                .font(.inter(.regular, size: 16, relativeTo: .body))
                .foregroundStyle(Paper.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("wishlist.empty")
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 80)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    /// A photo still being prepared.
    private var addingCell: some View {
        Paper.background
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ProgressView()
                    .tint(Paper.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Adding photos…"))
            .accessibilityIdentifier("wishlist.adding")
    }

    private func cell(_ photo: WishlistPhoto, number: Int) -> some View {
        Button {
            viewing = photo
        } label: {
            Paper.background
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    WishlistThumbnail(book: book, photo: photo)
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Photo \(number)"))
        .accessibilityIdentifier("wishlist.cell")
        .contextMenu {
            Button {
                pendingDelete = photo
            } label: {
                Label("Delete photo", systemImage: "trash")
            }
        }
    }
}

/// A photo's small square picture, filled edge to edge.
private struct WishlistThumbnail: View {
    let book: WishlistBook
    let photo: WishlistPhoto
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                Paper.fill
            }
        }
        .task(id: photo.id) {
            image = await book.thumbnail(of: photo)
        }
    }
}

// MARK: - Whole screen

/// One photo on the whole screen: swipe to the next or previous one, pinch (or tap twice)
/// to zoom, the bin to delete it (with a confirmation).
struct WishlistPhotoViewer: View {
    let book: WishlistBook

    @Environment(\.dismiss) private var dismiss
    @State private var current: UUID
    @State private var confirmDelete = false

    init(book: WishlistBook, start: UUID) {
        self.book = book
        _current = State(initialValue: start)
    }

    var body: some View {
        let photos = book.photos
        let index = photos.firstIndex { $0.id == current } ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("wishlist.viewer.close")

                Spacer()
                Text(verbatim: "\(index + 1) / \(photos.count)")
                    .font(.inter(.semibold, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Paper.ink)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Photo \(index + 1) of \(photos.count)"))
                    .accessibilityValue(Text(verbatim: "\(index + 1)/\(photos.count)"))
                    .accessibilityIdentifier("wishlist.viewer.position")
                Spacer()

                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Paper.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete photo"))
                .accessibilityIdentifier("wishlist.viewer.delete")
                .confirmationDialog(Text("Delete this photo?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button {
                        delete(at: index, in: photos)
                    } label: {
                        Text("Delete")
                    }
                    .accessibilityIdentifier("wishlist.confirmDelete")
                    Button(role: .cancel) {
                    } label: {
                        Text("Cancel")
                    }
                } message: {
                    Text("It is deleted from the app only, not from your photo library.")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 52)

            TabView(selection: $current) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { number, photo in
                    ZoomablePhoto(book: book, photo: photo)
                        .tag(photo.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Photo \(number + 1) of \(photos.count)"))
                        .accessibilityAddTraits(.isImage)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("wishlist.viewer")
        }
        .background(Paper.background.ignoresSafeArea())
        .tint(Paper.ink)
        .onChange(of: photos.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    /// Deletes the photo on screen and shows the next one (or the one before; none: closes).
    private func delete(at index: Int, in photos: [WishlistPhoto]) {
        guard photos.indices.contains(index) else { return }
        let deleted = photos[index].id
        let neighbor = photos.indices.contains(index + 1) ? photos[index + 1] : photos.indices.contains(index - 1) ? photos[index - 1] : nil
        if let neighbor {
            current = neighbor.id
        }
        book.delete(deleted)
        if neighbor == nil {
            dismiss()
        }
    }
}

/// A photo that loads its whole picture when it comes on screen.
private struct ZoomablePhoto: View {
    let book: WishlistBook
    let photo: WishlistPhoto
    @State private var image: UIImage?

    var body: some View {
        ZoomableImage(image: image)
            .overlay {
                if image == nil {
                    ProgressView()
                        .tint(Paper.ink)
                }
            }
            .task(id: photo.id) {
                image = await book.image(of: photo)
            }
    }
}

/// Pinch to zoom (1× to 4×) and tap twice to zoom in or out, with UIKit's own scroll view.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?

    func makeUIView(context: Context) -> ZoomingImageView {
        ZoomingImageView()
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.setImage(image)
    }
}

final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setImage(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        setZoomScale(1, animated: false)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Not zoomed: the photo fits the screen (also after turning the iPad).
        if zoomScale <= minimumZoomScale {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
