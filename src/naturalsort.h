#pragma once

#include <QString>

// Human page ordering.
//
// A plain alphabetical sort puts "10.webp" between "1.webp" and "2.webp", which
// scrambles every comic ever numbered without zero padding. naturalLess walks
// both strings together and compares runs of digits as numbers, so 2 < 10, while
// everything else compares case-insensitively.
bool naturalLess(const QString &a, const QString &b);
