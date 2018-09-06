# frozen_string_literal: true

require 'benchmark'

require_relative 'trend/version'

module Benchmark
  module Trend
    def self.private_module_function(method)
      module_function(method)
      private_class_method(method)
    end

    # Generate a range of inputs spaced by powers.
    #
    # The default range is generated in the multiples of 8.
    #
    # @example
    #   Benchmark::Trend.range(8, 8 << 10)
    #   # => [8, 64, 512, 4096, 8192]
    #
    # @param [Integer] start
    # @param [Integer] limit
    # @param [Integer] multi
    #
    # @api public
    def range(start, limit, multi: 8)
      check_greater(start, 0)
      check_greater(limit, start)
      check_greater(multi, 2)

      items = []
      count = start
      items << count
      (limit/multi).times do
        count *= multi
        break if count >= limit
        items << count
      end
      items << limit if start != limit
      items
    end
    module_function :range

    # Check if expected value is greater than minimum
    #
    # @param [Numeric] expected
    # @param [Numeric] min
    #
    # @raise [ArgumentError]
    #
    # @api private
    def check_greater(expected, min)
      unless expected >= min
        raise ArgumentError,
              "Range value: #{expected} needs to be greater than #{min}"
      end
    end
    private_module_function :check_greater

    # Gather times for each input against an algorithm
    #
    # @param [Array[Numeric]] data
    #   the data to run measurements for
    #
    # @return [Array[Array, Array]]
    #
    # @api public
    def measure_execution_time(data = nil, &work)
      inputs = data || range(1, 10_000)

      times = []

      inputs.each do |input|
        GC.start
        times << ::Benchmark.realtime do
          work.(input)
        end
      end
      [inputs, times]
    end
    module_function :measure_execution_time

    # Finds a line of best fit that approximates linear function
    #
    # Function form: y = ax + b
    #
    # @param [Array[Numeric]] xs
    #   the data points along X axis
    #
    # @param [Array[Numeric]] ys
    #   the data points along Y axis
    #
    # @return [Numeric, Numeric, Numeric]
    #   return a slope, b intercept and rr correlation coefficient
    #
    # @api public
    def fit_linear(xs, ys)
      fit(xs, ys)
    end
    module_function :fit_linear

    # Find a line of best fit that approximates logarithmic function
    #
    # Model form: y = a*lnx + b
    #
    # @param [Array[Numeric]] xs
    #   the data points along X axis
    #
    # @param [Array[Numeric]] ys
    #   the data points along Y axis
    #
    # @return [Numeric, Numeric, Numeric]
    #   returns a, b, and rr values
    #
    # @api public
    def fit_logarithmic(xs, ys)
      fit(xs, ys, tran_x: ->(x) { Math.log(x)})
    end
    module_function :fit_logarithmic

    alias fit_log fit_logarithmic
    module_function :fit_log

    # Finds a line of best fit that approxmimates power function
    #
    # Function form: y = ax^b
    #
    # @return [Numeric, Numeric, Numeric]
    #   returns a, b, and rr values
    #
    # @api public
    def fit_power(xs, ys)
      a, b, rr = fit(xs, ys, tran_x: ->(x) { Math.log(x)},
                            tran_y: ->(y) { Math.log(y)})

      [Math.exp(b), a, rr]
    end
    module_function :fit_power

    # Find a line of best fit that approximates exponential function
    #
    # Model form: y = ab^x
    #
    # @return [Numeric, Numeric, Numeric]
    #   returns a, b, and rr values
    #
    # @api public
    def fit_exponential(xs, ys)
      a, b, rr = fit(xs, ys, tran_y: ->(y) { Math.log(y) })

      [Math.exp(a), Math.exp(b), rr]
    end
    module_function :fit_exponential

    alias fit_exp fit_exponential
    module_function :fit_exp

    # Fit the performance measurements to construct a model with 
    # slope and intercept parameters that minimize the error.
    #
    # @param [Array[Numeric]] xs
    #   the data points along X axis
    #
    # @param [Array[Numeric]] ys
    #   the data points along Y axis
    #
    # @return [Array[Numeric, Numeric, Numeric]
    #   returns slope, intercept and model's goodness-of-fit
    #
    # @api public
    def fit(xs, ys, tran_x: ->(x) { x }, tran_y: ->(y) { y })
      n      = 0
      sum_x  = 0.0
      sum_x2 = 0.0
      sum_y  = 0.0
      sum_y2 = 0.0
      sum_xy = 0.0

      xs.zip(ys).each do |x, y|
        n        += 1
        sum_x    += tran_x.(x)
        sum_y    += tran_y.(y)
        sum_x2   += tran_x.(x) ** 2
        sum_y2   += tran_y.(y) ** 2
        sum_xy   += tran_x.(x) * tran_y.(y)
      end

      txy = n * sum_xy - sum_x * sum_y
      tx  = n * sum_x2 - sum_x ** 2
      ty  = n * sum_y2 - sum_y ** 2

      slope       = txy / tx
      intercept   = (sum_y - slope * sum_x) / n
      residual_sq = (txy ** 2) / (tx * ty)

      [slope, intercept, residual_sq]
    end
    module_function :fit

    def trend_format(type)
      case type
      when :linear
        "%.2f*n + %.2f"
      when :logarithmic
        "%.2f*ln(x) + %.2f"
      when :power
        "%.2fn^%.2f"
      when :exponential
        "%.2f * %.2f^n"
      else
        "Uknown type: '#{type}'"
      end
    end
    module_function :trend_format

    # Infer trend from the execution times
    #
    # Fits the executiom times for each range to several fit models.
    #
    # @yieldparam work
    #
    # @return [Array[Symbol, Hash]]
    #   the best fitting and all the trends
    #
    # @api public
    def infer_trend(data, &work)
      # the trends to consider
      fit_types = [:exponential, :power, :linear, :logarithmic]

      ns, times = *measure_execution_time(data, &work)
      best_fit = :none
      best_residual = 0
      fitted = {}
      fit_types.each do |fit|
        a, b, rr = *send(:"fit_#{fit}", ns, times)
        fitted[fit] = {trend: trend_format(fit) % [a, b],
                      slope: a, intercept: b, residual: rr}
        if rr > best_residual
          best_residual = rr
          best_fit = fit
        end
      end

      [best_fit, fitted]
    end
    module_function :infer_trend
  end # Trend
end # Benchmark