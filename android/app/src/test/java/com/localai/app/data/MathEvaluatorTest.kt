package com.localai.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MathEvaluatorTest {

    private fun assertEval(expr: String, expected: Double) {
        val got = MathEvaluator.evaluate(expr)
        assertEquals("eval($expr)", expected, got ?: Double.NaN, 1e-9)
    }

    @Test
    fun `basic arithmetic`() {
        assertEval("2+3*4", 14.0)
        assertEval("(2+3)*4", 20.0)
        assertEval("10/4", 2.5)
        assertEval("7%3", 1.0)
    }

    @Test
    fun `unary minus`() {
        assertEval("2*(-3)", -6.0)
        assertEval("3 - -2", 5.0)
        assertEval("-5+2", -3.0)
    }

    @Test
    fun `exponent`() {
        assertEval("2^3^2", 512.0)
        assertEval("100/2^2", 25.0)
    }

    @Test
    fun `functions and constants`() {
        assertEval("sqrt(16)", 4.0)
        assertEval("abs(-7)", 7.0)
        assertEval("min(1,max(2,3))", 1.0)
        assertEval("pow(2,10)", 1024.0)
        assertEval("floor(3.7)", 3.0)
        assertEval("round(2.5)", 3.0)
        assertEval("(1+2)*(3+4)", 21.0)
        assertEval("max(1,2)+min(3,4)", 5.0)
        assertEquals(Math.PI, MathEvaluator.evaluate("pi") ?: 0.0, 1e-9)
    }

    @Test
    fun `scientific notation`() {
        assertEval("1e3", 1000.0)
        assertEval("2.5e-2", 0.025)
    }

    @Test
    fun `invalid expressions return null`() {
        assertNull(MathEvaluator.evaluate("2+"))
        assertNull(MathEvaluator.evaluate("1/0"))
        assertNull(MathEvaluator.evaluate("2*("))
        assertNull(MathEvaluator.evaluate("sqrt(-1)"))
        assertNull(MathEvaluator.evaluate("hello"))
        assertNull(MathEvaluator.evaluate(""))
    }
}
