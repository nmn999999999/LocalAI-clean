package com.localai.app.data

import kotlin.math.*

/** 安全数学表达式求值（Shunting-yard + RPN，纯 Kotlin 无崩溃风险）。 */
object MathEvaluator {

    private val binaryOps = setOf("+", "-", "*", "/", "%", "^", "min", "max", "pow")
    private val unaryOps = setOf(
        "u+", "u-", "sqrt", "abs", "round", "floor", "ceil",
        "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "log10", "exp"
    )

    private sealed class Token {
        data class Num(val v: Double) : Token()
        data class Op(val name: String) : Token()
        data class Const(val name: String) : Token()
        object LParen : Token()
        object RParen : Token()
        object Comma : Token()
    }

    fun evaluate(input: String): Double? {
        val cleaned = input.lowercase()
            .replace("×", "*")
            .replace("÷", "/")
            .replace("π", "pi")
        val tokens = tokenize(cleaned) ?: return null
        if (tokens.isEmpty()) return null

        // Shunting-yard → RPN
        val output = ArrayDeque<Token>()
        val stack = ArrayDeque<Token>()

        for (token in tokens) {
            when (token) {
                is Token.Num, is Token.Const -> output.addLast(token)
                is Token.Op -> {
                    val prec = precedence(token.name)
                    while (stack.isNotEmpty()) {
                        val top = stack.last()
                        if (top !is Token.Op) break
                        val topPrec = precedence(top.name)
                        val rightAssoc = token.name == "^"
                        if (topPrec > prec || (topPrec == prec && !rightAssoc && top.name != "^")) {
                            output.addLast(stack.removeLast())
                        } else break
                    }
                    stack.addLast(token)
                }
                Token.LParen -> stack.addLast(token)
                Token.Comma -> {
                    while (stack.isNotEmpty() && stack.last() != Token.LParen) {
                        output.addLast(stack.removeLast())
                    }
                }
                Token.RParen -> {
                    var found = false
                    while (stack.isNotEmpty()) {
                        val top = stack.last()
                        if (top == Token.LParen) {
                            stack.removeLast(); found = true; break
                        }
                        output.addLast(stack.removeLast())
                    }
                    if (!found) return null
                    val fn = stack.lastOrNull()
                    if (fn is Token.Op && isFunction(fn.name)) {
                        output.addLast(stack.removeLast())
                    }
                }
            }
        }
        while (stack.isNotEmpty()) {
            val top = stack.removeLast()
            if (top == Token.LParen) return null
            output.addLast(top)
        }

        // RPN 求值
        val values = ArrayDeque<Double>()
        for (token in output) {
            when (token) {
                is Token.Num -> values.addLast(token.v)
                is Token.Const -> values.addLast(if (token.name == "pi") PI else E)
                is Token.Op -> {
                    val n = if (token.name in binaryOps) 2 else 1
                    if (values.size < n) return null
                    val b = if (n == 2) values.removeLast() else 0.0
                    val a = values.removeLast()
                    val r = compute(token.name, a, b) ?: return null
                    values.addLast(r)
                }
                else -> return null
            }
        }
        return if (values.size == 1) values.first() else null
    }

    private fun compute(op: String, a: Double, b: Double): Double? = when (op) {
        "+" -> a + b
        "-" -> a - b
        "u+" -> a
        "u-" -> -a
        "*" -> a * b
        "/" -> if (b == 0.0) null else a / b
        "%" -> if (b == 0.0) null else a % b
        "^" -> a.pow(b)
        "sqrt" -> if (a >= 0) sqrt(a) else null
        "abs" -> abs(a)
        "round" -> if (a >= 0) floor(a + 0.5) else ceil(a - 0.5) // 四舍五入（与 iOS 一致）
        "floor" -> floor(a)
        "ceil" -> ceil(a)
        "sin" -> sin(a)
        "cos" -> cos(a)
        "tan" -> if (cos(a) == 0.0) null else tan(a)
        "asin" -> if (a in -1.0..1.0) asin(a) else null
        "acos" -> if (a in -1.0..1.0) acos(a) else null
        "atan" -> atan(a)
        "log", "log10" -> if (a > 0) log10(a) else null
        "ln" -> if (a > 0) ln(a) else null
        "exp" -> exp(a)
        "min" -> min(a, b)
        "max" -> max(a, b)
        "pow" -> a.pow(b)
        else -> null
    }

    private fun tokenize(input: String): List<Token>? {
        val tokens = mutableListOf<Token>()
        val chars = input.toCharArray()
        var idx = 0
        var expectOperand = true

        while (idx < chars.size) {
            val c = chars[idx]
            if (c.isWhitespace()) { idx++; continue }
            if (c.isDigit() || c == '.') {
                val sb = StringBuilder()
                while (idx < chars.size && (chars[idx].isDigit() || chars[idx] == '.')) {
                    sb.append(chars[idx]); idx++
                }
                // 科学计数法 1e3 / 2.5e-2
                if (idx + 1 < chars.size && (chars[idx] == 'e' || chars[idx] == 'E')) {
                    val next = chars[idx + 1]
                    if (next.isDigit() || next == '+' || next == '-') {
                        sb.append('e'); idx++
                        if (chars[idx] == '+' || chars[idx] == '-') { sb.append(chars[idx]); idx++ }
                        while (idx < chars.size && chars[idx].isDigit()) { sb.append(chars[idx]); idx++ }
                    }
                }
                val v = sb.toString().toDoubleOrNull() ?: return null
                tokens.add(Token.Num(v))
                expectOperand = false
                continue
            }
            if (c.isLetter()) {
                val sb = StringBuilder()
                while (idx < chars.size && chars[idx].isLetter()) { sb.append(chars[idx]); idx++ }
                when (val name = sb.toString().lowercase()) {
                    "pi", "π" -> { tokens.add(Token.Const("pi")); expectOperand = false }
                    "e" -> { tokens.add(Token.Const("e")); expectOperand = false }
                    else -> {
                        if (!isFunction(name)) return null
                        tokens.add(Token.Op(name)); expectOperand = true
                    }
                }
                continue
            }
            when (c) {
                '+', '-', '*', '/', '%', '^' -> {
                    if ((c == '+' || c == '-') && expectOperand) {
                        tokens.add(Token.Op(if (c == '-') "u-" else "u+"))
                    } else {
                        tokens.add(Token.Op(c.toString()))
                    }
                    expectOperand = true; idx++
                }
                '(', '（' -> { tokens.add(Token.LParen); expectOperand = true; idx++ }
                ')', '）' -> { tokens.add(Token.RParen); expectOperand = false; idx++ }
                ',', '，' -> { tokens.add(Token.Comma); expectOperand = true; idx++ }
                else -> return null
            }
        }
        return tokens
    }

    private fun isFunction(name: String) = name in unaryOps || name in binaryOps

    private fun precedence(op: String): Int = when (op) {
        "+", "-" -> 1
        "*", "/", "%" -> 2
        "^" -> 3
        else -> 4
    }
}
