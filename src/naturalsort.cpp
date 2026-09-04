#include "naturalsort.h"

namespace {

// Length of the digit run starting at `i`, and its value as a big-ish integer.
// Leading zeros are skipped for the value but remembered so that "01" sorts
// before "1" when the numbers are otherwise equal.
struct Digits {
    int length = 0;
    int zeros = 0;
    QString value;
};

Digits digitsAt(const QString &s, int i)
{
    Digits d;
    while (i + d.length < s.size() && s.at(i + d.length).isDigit())
        ++d.length;
    int j = i;
    while (j < i + d.length && s.at(j) == u'0') {
        ++j;
        ++d.zeros;
    }
    d.value = s.mid(j, i + d.length - j);
    return d;
}

} // namespace

bool naturalLess(const QString &a, const QString &b)
{
    int i = 0, j = 0;
    while (i < a.size() && j < b.size()) {
        const QChar ca = a.at(i);
        const QChar cb = b.at(j);

        if (ca.isDigit() && cb.isDigit()) {
            const Digits da = digitsAt(a, i);
            const Digits db = digitsAt(b, j);
            // Compare as numbers: shorter (after stripping zeros) is smaller,
            // equal length falls back to lexical order of the digits.
            if (da.value.size() != db.value.size())
                return da.value.size() < db.value.size();
            const int cmp = QString::compare(da.value, db.value);
            if (cmp != 0)
                return cmp < 0;
            if (da.zeros != db.zeros)
                return da.zeros > db.zeros; // "01" before "1"
            i += da.length;
            j += db.length;
            continue;
        }

        const QChar la = ca.toCaseFolded();
        const QChar lb = cb.toCaseFolded();
        if (la != lb)
            return la < lb;
        ++i;
        ++j;
    }
    if (a.size() != b.size())
        return a.size() < b.size();
    return QString::compare(a, b) < 0;
}
