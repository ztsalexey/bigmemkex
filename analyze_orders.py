#!/usr/bin/env python3
import json
import subprocess

# Current market prices
prices = {
    'WETH': 1957.77,
    'DEGEN': 0.0006508,
    'AERO': 0.287943
}

# Get orders data
try:
    result = subprocess.run([
        'curl', '-X', 'GET', 'https://staging-api.claw2claw.2bb.dev/api/orders',
        '-H', 'Authorization: Bearer claw_XrG6K7A01UBLlQB5c5Ua9nr31i-tx36w',
        '-s'
    ], capture_output=True, text=True)
    
    data = json.loads(result.stdout)
    active_orders = [o for o in data['orders'] if o['active'] and not o['isExpired']]
    
    print(f"Found {len(active_orders)} active orders")
    
    arbitrage_opportunities = []
    
    for order in active_orders:
        sell_token = order['sellToken']
        buy_token = order['buyToken']
        amount_in = float(order['amountIn'])
        min_amount_out = float(order['minAmountOut'])
        sell_decimals = order['sellTokenDecimals']
        buy_decimals = order['buyTokenDecimals']
        
        # Convert to actual token amounts
        sell_amount = amount_in / (10 ** sell_decimals)
        buy_amount = min_amount_out / (10 ** buy_decimals)
        
        # Check for arbitrage opportunities
        if sell_token in prices and buy_token == 'USDC':
            # Someone selling token for USDC (we could buy cheap and sell at market)
            implied_price = buy_amount / sell_amount
            market_price = prices[sell_token]
            
            if implied_price < market_price * 0.98:  # Selling at least 2% below market
                profit_pct = ((market_price - implied_price) / implied_price) * 100
                arbitrage_opportunities.append({
                    'orderId': order['orderId'],
                    'type': 'buy_cheap',
                    'token': sell_token,
                    'implied_price': implied_price,
                    'market_price': market_price,
                    'profit_pct': profit_pct,
                    'token_amount': sell_amount,
                    'usd_cost': buy_amount
                })
                print(f"OPPORTUNITY: Order {order['orderId']} - Buy {sell_amount:.6f} {sell_token} for ${buy_amount:.2f} (${implied_price:.6f} vs market ${market_price:.6f}, {profit_pct:.1f}% profit)")
        
        elif buy_token in prices and sell_token == 'USDC':
            # Someone buying token with USDC (they're offering high price for token)
            implied_price = sell_amount / buy_amount
            market_price = prices[buy_token]
            
            if implied_price > market_price * 1.02:  # Buying at least 2% above market
                profit_pct = ((implied_price - market_price) / market_price) * 100
                arbitrage_opportunities.append({
                    'orderId': order['orderId'],
                    'type': 'sell_high',
                    'token': buy_token,
                    'implied_price': implied_price,
                    'market_price': market_price,
                    'profit_pct': profit_pct,
                    'token_amount': buy_amount,
                    'usd_revenue': sell_amount
                })
                print(f"OPPORTUNITY: Order {order['orderId']} - Sell {buy_amount:.6f} {buy_token} for ${sell_amount:.2f} (${implied_price:.6f} vs market ${market_price:.6f}, {profit_pct:.1f}% profit)")
    
    if arbitrage_opportunities:
        best = max(arbitrage_opportunities, key=lambda x: x['profit_pct'])
        print(f"\nBest opportunity: Order {best['orderId']} with {best['profit_pct']:.1f}% profit")
        print(json.dumps(best, indent=2))
    else:
        print("\nNo profitable arbitrage opportunities found")
        
except Exception as e:
    print(f"Error: {e}")