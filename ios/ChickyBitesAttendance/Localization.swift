import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case urdu

    static let storageKey = "cb.language"
    var id: String { rawValue }
    var resourceCode: String { self == .urdu ? "ur" : "en" }
    // UIDatePicker on iOS 26.6.1 aborts while applying the Unicode `nu-latn`
    // locale extension. Pakistan's standard English and Urdu locales already
    // render dates with Latin digits, so use their canonical identifiers. This
    // keeps the full Urdu UI and English numbers without triggering UIKit's
    // compact date-picker locale crash.
    var locale: Locale { Locale(identifier: self == .urdu ? "ur_PK" : "en_PK") }
    var layoutDirection: LayoutDirection { self == .urdu ? .rightToLeft : .leftToRight }
    var switchTitle: String { self == .urdu ? "English" : "اردو" }
}

enum L10n {
    static var currentLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? "") ?? .english
    }

    static func text(_ key: String, language: AppLanguage = currentLanguage) -> String {
        guard language == .urdu else { return latinDigits(key) }
        if let exactTranslation = dynamicUrdu[key.lowercased()] {
            return latinDigits(exactTranslation)
        }
        let bundle: Bundle
        if let path = Bundle.main.path(forResource: language.resourceCode, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .main
        }
        let localized = bundle.localizedString(forKey: key, value: key, table: nil)
        if localized != key { return latinDigits(localized) }
        return latinDigits(dynamicUrdu[key.lowercased()] ?? translatedCode(key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        latinDigits(String(format: text(key), locale: Locale(identifier: "en_PK"), arguments: arguments))
    }

    static func latinDigits(_ value: String) -> String {
        let source = Array("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹")
        let target = Array("01234567890123456789")
        let map = Dictionary(uniqueKeysWithValues: zip(source, target))
        return String(value.map { map[$0] ?? $0 })
    }

    static func date(_ value: Date, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .none) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = currentLanguage.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Karachi")
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return latinDigits(formatter.string(from: value))
    }

    static func monthYear(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = currentLanguage.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Karachi")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return latinDigits(formatter.string(from: value))
    }

    private static func translatedCode(_ value: String) -> String {
        let readable = value.replacingOccurrences(of: "_", with: " ").sentenceCased
        return readable.split(separator: " ").map { dynamicUrdu[String($0).lowercased()] ?? String($0) }.joined(separator: " ")
    }

    /// Dictionary literals normally terminate the process when a duplicate key
    /// slips into a large translation table. Keep the convenient literal syntax,
    /// but make duplicate entries deterministic (the last translation wins) so a
    /// localization mistake can never crash the app during launch.
    private struct TranslationLookup<Key: Hashable, Value>: ExpressibleByDictionaryLiteral {
        private var storage: [Key: Value] = [:]

        init(dictionaryLiteral elements: (Key, Value)...) {
            for (key, value) in elements { storage[key] = value }
        }

        subscript(key: Key) -> Value? { storage[key] }
    }

    private static let dynamicUrdu: TranslationLookup<String, String> = [
        "owner": "مالک", "super admin": "سپر ایڈمن", "hr admin": "ایچ آر ایڈمن",
        "payroll admin": "پے رول ایڈمن", "payroll approver": "پے رول منظور کنندہ",
        "manager": "مینیجر", "employee": "ملازم", "system": "سسٹم", "light": "لائٹ", "dark": "ڈارک",
        "active": "فعال", "inactive": "غیر فعال", "present": "حاضر", "absent": "غیر حاضر",
        "pending": "زیر التواء", "approved": "منظور شدہ", "rejected": "مسترد شدہ", "cancelled": "منسوخ",
        "completed": "مکمل", "draft": "مسودہ", "submitted": "جمع شدہ", "locked": "مقفل", "paid": "ادا شدہ",
        "open": "کھلا", "resolved": "حل شدہ", "failed": "ناکام", "healthy": "درست", "enrolled": "اندراج شدہ",
        "available": "دستیاب", "unavailable": "دستیاب نہیں", "earning": "آمدن", "deduction": "کٹوتی", "reversal": "واپسی",
        "sick leave": "بیماری کی چھٹی", "urgent leave": "ہنگامی چھٹی", "normal leave": "عام چھٹی",
        "late check-in": "دیر سے چیک اِن", "early check-out": "جلد چیک آؤٹ", "overtime": "اضافی وقت", "extra food": "اضافی کھانا",
        "bank transfer": "بینک ٹرانسفر", "cash": "نقد", "cheque": "چیک", "other": "دیگر",
        "full time": "کل وقتی", "part time": "جز وقتی", "intern": "انٹرن", "contract": "معاہدہ", "temporary": "عارضی",
        "probation": "آزمائشی مدت", "onboarding": "شمولیتی کارروائی", "offboarding": "علیحدگی کی کارروائی",
        "branch": "برانچ", "organization": "ادارہ", "fixed": "مقررہ", "percentage": "فیصد",
        "per minute": "فی منٹ", "per hour": "فی گھنٹہ", "per occurrence": "فی بار",
        "next pay": "اگلی تنخواہ", "minutes": "منٹ", "unpaid": "بلا تنخواہ", "my request": "میری درخواست",
        "active employees": "فعال ملازمین", "present today": "آج حاضر", "absent today": "آج غیر حاضر",
        "pending leaves": "زیر التواء چھٹیاں", "today’s status": "آج کی صورتحال", "pending leave": "زیر التواء چھٹی",
        "loading attendance": "حاضری لوڈ ہو رہی ہے", "getting today’s register…": "آج کا حاضری رجسٹر حاصل کیا جا رہا ہے…",
        "loading updates": "تازہ معلومات لوڈ ہو رہی ہیں", "getting notifications and reports…": "اطلاعات اور رپورٹس حاصل کی جا رہی ہیں…",
        "payslips": "پے سلپس", "my payslips": "میری پے سلپس", "branch radius": "برانچ کا رداس",
        "your secure access": "آپ کی محفوظ رسائی", "unmarked": "نشان نہیں لگایا گیا", "assigned branch": "تفویض کردہ برانچ",
        "leave management": "چھٹیوں کا انتظام", "leave balance": "چھٹیوں کا بیلنس", "leave policies": "چھٹی کی پالیسیاں",
        "break": "وقفہ", "no payroll runs": "کوئی پے رول رن نہیں",
        "days per year": "دن سالانہ", "protected attendance records are waiting to sync.": "محفوظ حاضری کے ریکارڈ مطابقت پذیر ہونے کے منتظر ہیں۔",
        "certificate": "سرٹیفکیٹ", "warning": "تنبیہ", "medical": "طبی", "termination": "ملازمت کا اختتام",
        "under review": "زیر جائزہ", "accepted": "قبول شدہ", "payment": "ادائیگی", "earnings": "آمدن", "deductions": "کٹوتیاں",
        "quantity rate": "مقدار کے حساب سے شرح", "percentage base": "بنیادی تنخواہ کا فیصد", "custom": "حسب ضرورت",
        "enroll employee face": "ملازم کے چہرے کا اندراج", "verify your face": "اپنے چہرے کی تصدیق کریں",
        "scanning automatically…": "خودکار اسکین جاری ہے…", "save employee face": "ملازم کا چہرہ محفوظ کریں",
        "absence": "غیر حاضری", "unpaid leave": "بلا تنخواہ چھٹی", "loan": "قرض", "tax": "ٹیکس",
        "reimbursement": "اخراجات کی واپسی", "bonus": "بونس", "penalty": "جرمانہ", "allowance": "الاؤنس",
        "disputed": "اعتراض شدہ", "applied": "لاگو شدہ", "reversed": "واپس شدہ",
        "position one face inside the oval": "ایک چہرہ بیضوی دائرے کے اندر رکھیں",
        "face verified": "چہرے کی تصدیق ہو گئی", "hold still for a moment": "ایک لمحہ ساکن رہیں",
        "blink once": "ایک بار پلک جھپکائیں", "blink once and turn your head left": "ایک بار پلک جھپکائیں اور سر بائیں موڑیں",
        "blink once and turn your head right": "ایک بار پلک جھپکائیں اور سر دائیں موڑیں",
        "something went wrong. please try again.": "کچھ غلط ہو گیا۔ دوبارہ کوشش کریں۔",
        "filters": "فلٹرز", "records": "ریکارڈز", "worked": "کام", "min": "منٹ", "attendance history": "حاضری کی تفصیل", "my attendance history": "میری حاضری کی تفصیل",
        "view attendance history": "حاضری کی تفصیل دیکھیں", "load older attendance": "پرانی حاضری لوڈ کریں",
        "attendance filters": "حاضری کے فلٹرز", "days": "دن", "late": "تاخیر", "in": "آمد", "out": "روانگی",
        "no attendance records": "حاضری کا کوئی ریکارڈ نہیں", "records in the selected period will appear here.": "منتخب مدت کے ریکارڈ یہاں دکھائی دیں گے۔",
        "loading history": "حاضری کی تفصیل لوڈ ہو رہی ہے", "getting your attendance records…": "آپ کے حاضری ریکارڈ حاصل کیے جا رہے ہیں…",
        "request correction": "درستگی کی درخواست", "correct check-in": "چیک اِن درست کریں", "correct check-out": "چیک آؤٹ درست کریں",
        "explain what should be corrected": "وضاحت کریں کہ کیا درست کرنا ہے", "submit correction request": "درستگی کی درخواست جمع کریں",
        "correction": "درستگی", "advanced reports": "تفصیلی رپورٹس", "report filters": "رپورٹ کے فلٹرز",
        "filter attendance, leave, payroll, marking method, overrides, and dates.": "حاضری، چھٹی، تنخواہ، حاضری کے طریقے، اوور رائیڈ اور تاریخ کے مطابق فلٹر کریں۔",
        "loading report": "رپورٹ لوڈ ہو رہی ہے", "applying your filters…": "آپ کے فلٹرز لاگو کیے جا رہے ہیں…",
        "no report records": "رپورٹ کا کوئی ریکارڈ نہیں", "change the filters or date range and try again.": "فلٹر یا تاریخ کی مدت بدل کر دوبارہ کوشش کریں۔",
        "load older records": "پرانے ریکارڈ لوڈ کریں", "marking method": "حاضری کا طریقہ", "restaurant ip": "ریستوران کا IP",
        "gps": "GPS", "manager override": "مینیجر اوور رائیڈ", "offline verified": "آف لائن تصدیق شدہ",
        "override": "اوور رائیڈ", "used": "استعمال ہوا", "not used": "استعمال نہیں ہوا", "all employees": "تمام ملازمین",
        "operations health": "آپریشنز کی صحت", "all core services are responding.": "تمام بنیادی سروسز کام کر رہی ہیں۔",
        "health information is unavailable.": "صحت کی معلومات دستیاب نہیں۔", "backend connection": "بیک اینڈ کنکشن",
        "connected": "منسلک", "branch location": "برانچ کا مقام", "needs configuration": "ترتیب درکار ہے", "ready": "تیار",
        "approved restaurant ips": "منظور شدہ ریستوران IP", "face enrollment": "چہرے کا اندراج", "schedules": "شیڈولز",
        "salary configuration": "تنخواہ کی ترتیب", "push delivery": "اطلاع کی ترسیل", "rejected attendance (7 days)": "مسترد حاضری (7 دن)",
        "ios diagnostics (7 days)": "iOS تشخیصی معلومات (7 دن)", "pending offline attendance": "زیر التواء آف لائن حاضری",
        "common rejection reasons": "عام مسترد ہونے کی وجوہات", "health information unavailable": "صحت کی معلومات دستیاب نہیں",
        "pull to refresh when the internet connection is available.": "انٹرنیٹ دستیاب ہونے پر نیچے کھینچ کر تازہ کریں۔",
        "diagnostics": "تشخیصی معلومات", "view diagnostics": "تشخیصی معلومات دیکھیں", "diagnostic detail": "تشخیصی تفصیل",
        "open an error to see its screen, build, device, time, and recommended action.": "خرابی کھول کر متاثرہ اسکرین، بلڈ، ڈیوائس، وقت اور تجویز کردہ حل دیکھیں۔",
        "severity": "شدت", "crashes": "کریشز", "errors": "خرابیاں", "warnings": "انتباہات", "information": "معلومات",
        "loading diagnostics": "تشخیصی معلومات لوڈ ہو رہی ہیں", "getting the latest app errors…": "ایپ کی تازہ خرابیاں حاصل کی جا رہی ہیں…",
        "no diagnostics found": "کوئی تشخیصی خرابی نہیں ملی", "no matching app errors were recorded for this branch.": "اس برانچ کے لیے کوئی مماثل ایپ خرابی ریکارڈ نہیں ہوئی۔",
        "load older diagnostics": "پرانی تشخیصی معلومات لوڈ کریں", "affected screen": "متاثرہ اسکرین", "build": "بلڈ",
        "loading team": "ٹیم لوڈ ہو رہی ہے", "getting employee and branch information…": "ملازمین اور برانچ کی معلومات حاصل کی جا رہی ہیں…",
        "loading leave": "چھٹی کی معلومات لوڈ ہو رہی ہیں", "getting requests, balances, and policies…": "درخواستیں، بیلنس اور پالیسیاں حاصل کی جا رہی ہیں…",
        "device model": "ڈیوائس ماڈل", "ios version": "iOS ورژن", "time": "وقت", "device reference": "ڈیوائس حوالہ",
        "suggested action": "تجویز کردہ حل", "unknown": "نامعلوم",
        "notification recovery": "اطلاعات کی بحالی", "retry": "دوبارہ کوشش", "retry all": "سب دوبارہ بھیجیں",
        "failed alerts for the organization. retried alerts are sent by the secure delivery service within one minute.": "ادارے کی ناکام اطلاعات۔ دوبارہ شامل کی گئی اطلاعات محفوظ ترسیلی سروس ایک منٹ کے اندر بھیجے گی۔",
        "loading failed notifications": "ناکام اطلاعات لوڈ ہو رہی ہیں", "checking delivery attempts…": "ترسیل کی کوششیں چیک کی جا رہی ہیں…",
        "no failed notifications": "کوئی ناکام اطلاع نہیں", "all recorded push deliveries are healthy or already queued.": "تمام ریکارڈ شدہ پش اطلاعات درست ہیں یا پہلے ہی قطار میں ہیں۔",
        "load older failures": "پرانی ناکامیاں لوڈ کریں", "retry every failed notification?": "ہر ناکام اطلاع دوبارہ بھیجیں؟",
        "they will be queued for the next secure delivery cycle.": "انہیں اگلی محفوظ ترسیل کے لیے قطار میں شامل کیا جائے گا۔",
        "review this screen and build, then compare repeated crashes from the same device model.": "اس اسکرین اور بلڈ کا جائزہ لیں، پھر اسی ڈیوائس ماڈل کے بار بار ہونے والے کریشز کا موازنہ کریں۔",
        "confirm account verification and authentication service health, then ask the user to sign in again.": "اکاؤنٹ تصدیق اور لاگ اِن سروس کی حالت چیک کریں، پھر صارف کو دوبارہ لاگ اِن کروائیں۔",
        "check the employee assignment, branch ip and gps settings, then retry the attendance action.": "ملازم کی تفویض، برانچ IP اور GPS کی ترتیبات چیک کرکے حاضری دوبارہ لگائیں۔",
        "check backend health and the selected date filters, then retry the report.": "بیک اینڈ کی حالت اور منتخب تاریخ کے فلٹرز چیک کرکے رپورٹ دوبارہ کھولیں۔",
        "open notification recovery and retry the failed deliveries.": "اطلاعات کی بحالی کھولیں اور ناکام ترسیلات دوبارہ بھیجیں۔",
        "retry the affected action and review repeated events from the same build and device model.": "متاثرہ عمل دوبارہ کریں اور اسی بلڈ و ڈیوائس ماڈل کے بار بار ہونے والے واقعات دیکھیں۔",
        "setup checklist": "ترتیب کی فہرست", "restaurant setup": "ریستوران کی ترتیب",
        "complete these items before using attendance and payroll with real employees.": "حقیقی ملازمین کے ساتھ حاضری اور تنخواہ استعمال کرنے سے پہلے یہ کام مکمل کریں۔",
        "branch location and ip": "برانچ کا مقام اور IP", "coordinates, 50-metre radius, and restaurant wi-fi": "کوآرڈینیٹس، 50 میٹر کا دائرہ اور ریستوران Wi-Fi",
        "employees and branch assignments": "ملازمین اور برانچ کی تفویض", "identity, contact details, role, and joining date": "شناخت، رابطہ، کردار اور شمولیت کی تاریخ",
        "attendance face enrollment": "حاضری کے لیے چہرے کا اندراج", "enroll every employee who will mark attendance": "حاضری لگانے والے ہر ملازم کا چہرہ درج کریں",
        "working days, check-in, checkout, breaks, and grace time": "کام کے دن، چیک اِن، چیک آؤٹ، وقفہ اور رعایتی وقت",
        "sick, urgent, and normal leave entitlements": "بیماری، ہنگامی اور عام چھٹی کی حقداریاں", "salary and payroll": "تنخواہ اور پے رول",
        "base salary, deductions, pay dates, and rules": "بنیادی تنخواہ، کٹوتیاں، ادائیگی کی تاریخیں اور قواعد",
        "notifications": "اطلاعات", "enable alerts and confirm delivery health": "اطلاعات فعال کریں اور ترسیل کی حالت دیکھیں",
        "help & guides": "مدد اور رہنمائی", "marking attendance": "حاضری لگانا", "if wi-fi or gps fails": "اگر Wi-Fi یا GPS ناکام ہو",
        "leave and corrections": "چھٹی اور درستگیاں", "salary details": "تنخواہ کی تفصیل", "manager essentials": "مینیجر کے ضروری کام", "owner essentials": "مالک کے ضروری کام",
        "open attendance and tap check in.": "حاضری کھولیں اور چیک اِن دبائیں۔", "keep one face inside the oval in even light.": "یکساں روشنی میں ایک چہرہ بیضوی دائرے کے اندر رکھیں۔",
        "use restaurant wi-fi or allow precise gps.": "ریستوران Wi-Fi استعمال کریں یا درست GPS کی اجازت دیں۔", "tap check out before leaving.": "جانے سے پہلے چیک آؤٹ دبائیں۔",
        "keep location permission enabled.": "مقام کی اجازت فعال رکھیں۔", "try near an entrance or window for a clearer gps reading.": "بہتر GPS کے لیے داخلی دروازے یا کھڑکی کے قریب کوشش کریں۔",
        "attendance can be protected offline when valid gps and face evidence are available.": "درست GPS اور چہرے کی تصدیق دستیاب ہو تو حاضری آف لائن محفوظ کی جا سکتی ہے۔",
        "ask a manager to use an audited override only when both methods fail.": "دونوں طریقے ناکام ہوں تو مینیجر سے ریکارڈ شدہ اوور رائیڈ کی درخواست کریں۔",
        "submit leave with the correct dates and reason.": "درست تاریخ اور وجہ کے ساتھ چھٹی جمع کریں۔", "follow its status in the leave tab.": "چھٹی کے ٹیب میں اس کی حالت دیکھیں۔",
        "open attendance history to request a correction for an older day.": "پرانے دن کی درستگی کے لیے حاضری کی تفصیل کھولیں۔",
        "open salary to see your current summary.": "موجودہ خلاصہ دیکھنے کے لیے تنخواہ کھولیں۔", "every earning and deduction shows its date, reason, and calculation.": "ہر آمدن اور کٹوتی کی تاریخ، وجہ اور حساب دکھایا جاتا ہے۔",
        "use raise dispute when a transaction looks incorrect.": "غلط لین دین پر اعتراض درج کریں۔",
        "waiting for an internet connection.": "انٹرنیٹ کنکشن کا انتظار ہے۔",
        "location is unavailable. check location services and try again.": "مقام دستیاب نہیں۔ لوکیشن سروسز چیک کرکے دوبارہ کوشش کریں۔",
        "gps is required to save attendance offline.": "آف لائن حاضری محفوظ کرنے کے لیے GPS درکار ہے۔",
        "the face scan could not be prepared. please scan again.": "چہرے کا اسکین تیار نہیں ہو سکا۔ دوبارہ اسکین کریں۔",
        "the face challenge expired. please start again.": "چہرے کی تصدیق کا وقت ختم ہو گیا۔ دوبارہ شروع کریں۔",
        "latest information could not be refreshed. your saved information is still available.": "تازہ ترین معلومات ابھی اپ ڈیٹ نہیں ہو سکیں۔ آپ کی محفوظ معلومات دستیاب ہیں۔",
        "the service is temporarily unavailable. please try again in a moment.": "سروس عارضی طور پر دستیاب نہیں۔ کچھ دیر بعد دوبارہ کوشش کریں۔"
    ]
}

struct LanguageToggle: View {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.english.rawValue
    var onDarkBackground = false

    private var language: AppLanguage { AppLanguage(rawValue: storedLanguage) ?? .english }

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                storedLanguage = language == .english ? AppLanguage.urdu.rawValue : AppLanguage.english.rawValue
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(verbatim: language.switchTitle).fontWeight(.bold)
            }
            .font(.caption)
            .foregroundStyle(onDarkBackground ? .white : CBTheme.text)
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cbGlass(cornerRadius: 18, tint: onDarkBackground ? .white.opacity(0.08) : CBTheme.surface.opacity(0.12), interactive: true)
        .accessibilityLabel(language == .english ? "Switch to Urdu" : "انگریزی میں تبدیل کریں")
    }
}
