import Foundation

public enum ZTPSpecGenerator {

    // MARK: - Excel

    public static func excelSpec(
        title: String,
        author: String = "Zyquo Agent",
        sheets: [ExcelSheetSpec]
    ) -> String {
        var spec: [String: Any] = [
            "version": "ztp-excel/0.1",
            "workbook": ["title": title, "author": author],
        ]

        var sheetsArray: [[String: Any]] = []
        for sheet in sheets {
            var sheetDict: [String: Any] = ["name": sheet.name]
            var cells: [[String: Any]] = []
            for cell in sheet.cells {
                var cellDict: [String: Any] = [
                    "address": cell.address,
                    "value": cell.value,
                ]
                if let style = cell.style { cellDict["style"] = style }
                if let format = cell.format { cellDict["format"] = format }
                if let formula = cell.formula { cellDict["formula"] = formula }
                cells.append(cellDict)
            }
            sheetDict["cells"] = cells
            if !sheet.columnWidths.isEmpty { sheetDict["column_widths"] = sheet.columnWidths }
            sheetsArray.append(sheetDict)
        }
        spec["sheets"] = sheetsArray

        return jsonString(spec)
    }

    public struct ExcelSheetSpec {
        public let name: String
        public let cells: [ExcelCellSpec]
        public let columnWidths: [String: Double]

        public init(name: String, cells: [ExcelCellSpec], columnWidths: [String: Double] = [:]) {
            self.name = name
            self.cells = cells
            self.columnWidths = columnWidths
        }
    }

    public struct ExcelCellSpec {
        public let address: String
        public let value: Any
        public let style: String?
        public let format: String?
        public let formula: String?

        public init(address: String, value: Any, style: String? = nil, format: String? = nil, formula: String? = nil) {
            self.address = address
            self.value = value
            self.style = style
            self.format = format
            self.formula = formula
        }
    }

    // MARK: - Chart

    public static func chartSpec(
        type: String,
        title: String,
        data: [[String: Any]],
        xField: String,
        xLabel: String,
        series: [(field: String, label: String)],
        width: Int = 1000,
        height: Int = 600,
        theme: String = "zyquo-light"
    ) -> String {
        let spec: [String: Any] = [
            "version": "ztp-chart/0.1",
            "chart": [
                "type": type,
                "title": title,
                "width": width,
                "height": height,
                "theme": theme,
            ],
            "data": ["values": data],
            "x": ["field": xField, "label": xLabel],
            "y": ["label": title],
            "series": series.map { ["field": $0.field, "label": $0.label] },
            "grid": true,
        ]
        return jsonString(spec)
    }

    // MARK: - Docx

    public static func docxSpec(
        title: String,
        author: String = "Zyquo Agent",
        elements: [[String: Any]]
    ) -> String {
        let spec: [String: Any] = [
            "version": "ztp-docx/0.1",
            "document": ["title": title, "author": author],
            "sections": [
                ["elements": elements],
            ],
        ]
        return jsonString(spec)
    }

    // MARK: - Slides

    public static func slidesSpec(
        title: String,
        author: String = "Zyquo Agent",
        slides: [[String: Any]]
    ) -> String {
        let spec: [String: Any] = [
            "version": "ztp-slides/0.1",
            "presentation": ["title": title, "author": author],
            "slides": slides,
        ]
        return jsonString(spec)
    }

    // MARK: - Mail

    public static func mailSpec(
        from: String,
        to: [String],
        subject: String,
        body: String,
        bodyType: String = "markdown",
        attachments: [String] = []
    ) -> String {
        var message: [String: Any] = [
            "from": from,
            "to": to,
            "subject": subject,
            "body": ["type": bodyType, "content": body],
        ]
        if !attachments.isEmpty {
            message["attachments"] = attachments.map { ["path": $0] }
        }
        let spec: [String: Any] = [
            "version": "ztp-mail/0.1",
            "message": message,
        ]
        return jsonString(spec)
    }

    // MARK: - Message

    public static func messageSpec(
        channel: String = "imessage",
        to: [(name: String, address: String)],
        body: String
    ) -> String {
        let spec: [String: Any] = [
            "version": "ztp-message/0.1",
            "message": [
                "channel": channel,
                "to": to.map { ["name": $0.name, "address": $0.address] },
                "body": ["type": "plain", "content": body],
            ],
        ]
        return jsonString(spec)
    }

    // MARK: - JSON Helper

    private static func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
