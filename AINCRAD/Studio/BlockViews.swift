import AppKit
import SwiftUI

enum BlockStyle {
    static func fill(_ c: BlockCategory) -> Color { Color(nsColor: themeColor(c.hex)) }
    static func edge(_ c: BlockCategory) -> Color {
        Color(nsColor: (themeColor(c.hex).blended(withFraction: 0.25, of: .black) ?? .black))
    }
    static let font = Font.system(size: 12, weight: .bold, design: .rounded)
    static let nsFont = NSFont.systemFont(ofSize: 12, weight: .bold)
}

/// Scratch's puzzle-piece outline: a notch on top, a tab underneath (drawn below the frame so
/// the next block's notch sits on it). Hats get a rounded cap instead of a notch.
struct StatementShape: Shape {
    var hat = false
    var tab = true

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, rad: CGFloat = 5, nx: CGFloat = 14, nw: CGFloat = 20, n: CGFloat = 4
        var p = Path()
        if hat {
            p.move(to: CGPoint(x: 0, y: 14))
            p.addQuadCurve(to: CGPoint(x: min(96, w * 0.6), y: 6), control: CGPoint(x: min(40, w * 0.25), y: -6))
            p.addLine(to: CGPoint(x: w - rad, y: 6))
            p.addArc(tangent1End: CGPoint(x: w, y: 6), tangent2End: CGPoint(x: w, y: 6 + rad), radius: rad)
        } else {
            p.move(to: CGPoint(x: 0, y: rad))
            p.addArc(tangent1End: .zero, tangent2End: CGPoint(x: rad, y: 0), radius: rad)
            p.addLine(to: CGPoint(x: nx, y: 0))
            p.addLine(to: CGPoint(x: nx + 4, y: n))
            p.addLine(to: CGPoint(x: nx + nw - 4, y: n))
            p.addLine(to: CGPoint(x: nx + nw, y: 0))
            p.addLine(to: CGPoint(x: w - rad, y: 0))
            p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: rad), radius: rad)
        }
        p.addLine(to: CGPoint(x: w, y: h - rad))
        p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - rad, y: h), radius: rad)
        if tab {
            p.addLine(to: CGPoint(x: nx + nw, y: h))
            p.addLine(to: CGPoint(x: nx + nw - 4, y: h + n))
            p.addLine(to: CGPoint(x: nx + 4, y: h + n))
            p.addLine(to: CGPoint(x: nx, y: h))
        }
        p.addLine(to: CGPoint(x: rad, y: h))
        p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - rad), radius: rad)
        p.closeSubpath()
        return p
    }
}

/// Boolean reporters are hexagons, like Scratch.
struct HexShape: Shape {
    func path(in r: CGRect) -> Path {
        let i = r.height / 2
        var p = Path()
        p.move(to: CGPoint(x: i, y: 0))
        p.addLine(to: CGPoint(x: r.width - i, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: i))
        p.addLine(to: CGPoint(x: r.width - i, y: r.height))
        p.addLine(to: CGPoint(x: i, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: i))
        p.closeSubpath()
        return p
    }
}

/// The words, value slots and dropdowns of one block.
struct BlockLabel: View {
    let block: Block
    let spec: BlockSpec
    let live: Bool
    @EnvironmentObject var model: StudioModel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(BlockSpec.parse(spec.label).enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let t):
                    Text(t).font(BlockStyle.font).foregroundStyle(.white).fixedSize()
                case .input(let name):
                    InputSlot(owner: block.id, name: name, value: block.inputs[name],
                              boolean: name == "condition" || (spec.kind == .boolean && ["a", "b"].contains(name) && ["op.and", "op.or", "op.not"].contains(spec.op)),
                              live: live)
                case .field(let name):
                    FieldMenu(block: block, spec: spec, name: name, live: live)
                }
            }
        }
    }
}

struct InputSlot: View {
    let owner: String
    let name: String
    let value: Block?
    let boolean: Bool
    let live: Bool
    @EnvironmentObject var model: StudioModel
    @State private var targeted = false

    var body: some View {
        Group {
            if let v = value, v.literalValue == nil, let spec = BlockSpec.spec(v.op) {
                ReporterView(block: v, spec: spec, live: live)
            } else if boolean {
                HexShape().fill(Color.black.opacity(0.25)).frame(width: 38, height: 18)
            } else {
                literalField
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: targeted ? 2.5 : 0))
        .dropDestination(for: String.self) { items, _ in
            guard live, let payload = items.first.flatMap(BlockPayload.decode) else { return false }
            return model.dropReporter(payload, into: owner, slot: name)
        } isTargeted: { targeted = live && $0 }
    }

    private var literalField: some View {
        let text = value?.literalValue ?? ""
        let width = max(26, (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 16)
        return TextField("", text: Binding(get: { text }, set: { v in if let id = value?.id { model.setLiteral(id, v) } }))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .frame(width: min(width, 220), height: 18)
            .background(Capsule().fill(.white))
            .disabled(!live)
    }
}

struct FieldMenu: View {
    let block: Block
    let spec: BlockSpec
    let name: String
    let live: Bool
    @EnvironmentObject var model: StudioModel

    var body: some View {
        let value = block.fields[name] ?? ""
        let options = spec.options[name] ?? (BlockSpec.variableOps.contains(spec.op)
            ? Array(Set(ScriptTree.variableNames(model.scripts) + [value])).sorted() : [])
        Menu {
            ForEach(options, id: \.self) { o in Button(o) { model.setField(block.id, name, o) } }
            if BlockSpec.variableOps.contains(spec.op) {
                Divider()
                Button("New variable…") {
                    if let n = StudioPrompt.ask("Variable name", placeholder: "score"), !n.isEmpty { model.setField(block.id, name, n) }
                }
            }
        } label: {
            Text(value).font(BlockStyle.font).foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.black.opacity(0.18)))
        .disabled(!live)
    }
}

struct ReporterView: View {
    let block: Block
    let spec: BlockSpec
    let live: Bool
    @EnvironmentObject var model: StudioModel

    var body: some View {
        let label = BlockLabel(block: block, spec: spec, live: live)
            .padding(.horizontal, spec.kind == .boolean ? 12 : 8)
            .padding(.vertical, 3)
        Group {
            if spec.kind == .boolean {
                label.background(HexShape().fill(BlockStyle.fill(spec.category)))
                    .overlay(HexShape().stroke(BlockStyle.edge(spec.category), lineWidth: 1))
            } else {
                label.background(Capsule().fill(BlockStyle.fill(spec.category)))
                    .overlay(Capsule().stroke(BlockStyle.edge(spec.category), lineWidth: 1))
            }
        }
        .help(spec.help)
        .draggable(BlockPayload(block: block, fromCanvas: live).string)
        .contextMenu {
            if live { Button("Remove") { model.delete(block.id) } }
        }
    }
}

/// A statement or C-block on the canvas (or, with `live` false, in the palette).
struct StatementView: View {
    let block: Block
    let live: Bool
    @EnvironmentObject var model: StudioModel

    var body: some View {
        if let spec = BlockSpec.spec(block.op) {
            VStack(alignment: .leading, spacing: 0) {
                switch spec.kind {
                case .cBlock, .ifElse:
                    cBlock(spec)
                case .hat:
                    simple(spec, hat: true)
                default:
                    simple(spec, hat: false)
                }
                if live && spec.kind != .cap { DropGap(slot: .after(block.id)) }
            }
        }
    }

    private func header(_ spec: BlockSpec, hat: Bool, tab: Bool = true) -> some View {
        BlockLabel(block: block, spec: spec, live: live)
            .padding(.leading, 9)
            .padding(.trailing, 10)
            .padding(.top, hat ? 14 : 7)
            .padding(.bottom, 7)
            .background(StatementShape(hat: hat, tab: tab).fill(BlockStyle.fill(spec.category)))
            .overlay(StatementShape(hat: hat, tab: tab).stroke(BlockStyle.edge(spec.category), lineWidth: 1))
            .help(spec.help)
            .draggable(BlockPayload(block: block, fromCanvas: live).string)
            .contextMenu {
                if live {
                    Button("Duplicate") { model.duplicate(block.id) }
                    Button("Delete", role: .destructive) { model.delete(block.id) }
                }
            }
    }

    private func simple(_ spec: BlockSpec, hat: Bool) -> some View {
        header(spec, hat: hat, tab: spec.kind != .cap)
    }

    @ViewBuilder private func cBlock(_ spec: BlockSpec) -> some View {
        header(spec, hat: false)
        arm(spec, blocks: block.body ?? [], slot: .bodyTop(block.id))
        if spec.kind == .ifElse {
            Text("else").font(BlockStyle.font).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .frame(minWidth: 120, alignment: .leading)
                .background(Rectangle().fill(BlockStyle.fill(spec.category)))
            arm(spec, blocks: block.elseBody ?? [], slot: .elseTop(block.id))
        }
        StatementShape().fill(BlockStyle.fill(spec.category))
            .overlay(StatementShape().stroke(BlockStyle.edge(spec.category), lineWidth: 1))
            .frame(width: 120, height: 14)
    }

    private func arm(_ spec: BlockSpec, blocks: [Block], slot: ScriptTree.Slot) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(BlockStyle.fill(spec.category)).frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                if live { DropGap(slot: slot, minHeight: blocks.isEmpty ? 22 : 6) }
                ForEach(blocks) { StatementView(block: $0, live: live) }
            }
            .padding(.leading, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Where a dragged statement can land. Grows and shows a line while hovered.
struct DropGap: View {
    let slot: ScriptTree.Slot
    var minHeight: CGFloat = 6
    @EnvironmentObject var model: StudioModel
    @State private var targeted = false

    var body: some View {
        Rectangle()
            .fill(targeted ? Color.white.opacity(0.85) : Color.clear)
            .frame(width: targeted ? 140 : 120, height: targeted ? 5 : 1)
            .padding(.vertical, targeted ? 8 : max(0, (minHeight - 1) / 2))
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first.flatMap(BlockPayload.decode) else { return false }
                return model.drop(payload, at: slot)
            } isTargeted: { targeted = $0 }
            .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

enum StudioPrompt {
    static func ask(_ title: String, placeholder: String, initial: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
