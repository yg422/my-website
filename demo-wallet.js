import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'

export const supabase = createClient(
    'https://vichweflmhhepwkwdzdl.supabase.co',
    'sb_publishable_rvW7gmWbDiwm_0IB7L3rnQ_ulE6vcwG'
)

export async function requireSignedIn() {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) {
        window.location.replace('contact=styled.html')
        return null
    }
    return session.user
}

export async function loadWallet() {
    const { data: balance, error: balanceError } = await supabase.rpc('ensure_demo_wallet')
    if (balanceError) throw balanceError

    const { data: transactions, error: transactionsError } = await supabase
        .from('demo_transactions')
        .select('id, title, amount, created_at')
        .order('created_at', { ascending: false })
        .limit(30)
    if (transactionsError) throw transactionsError

    return {
        balance: Number(balance),
        transactions: (transactions || []).map((transaction) => ({
            title: transaction.title,
            amount: Number(transaction.amount),
            date: transaction.created_at
        }))
    }
}

export async function sendDemoTransfer(recipientEmail, amount) {
    const { data, error } = await supabase.rpc('transfer_demo_funds', {
        p_recipient_email: recipientEmail.trim(),
        p_amount: amount
    })
    if (error) throw error
    return {
        balance: Number(data.balance),
        recipientBalance: Number(data.recipient_balance),
        recipientName: data.recipient_name
    }
}

export async function withdrawDemoFunds(amount, method) {
    const { data, error } = await supabase.rpc('withdraw_demo_funds', {
        p_amount: amount,
        p_method: method
    })
    if (error) throw error
    return Number(data)
}

export const money = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD'
})

export function renderTransactions(transactions, container) {
    container.replaceChildren()
    transactions.forEach((transaction) => {
        const row = document.createElement('div')
        row.className = 'transaction'
        const info = document.createElement('div')
        info.className = 'transaction-info'
        const title = document.createElement('strong')
        title.textContent = transaction.title
            .replace(/^Demo\s+/i, '')
            .replace(/((?:Sent to|Received from)\s+)[^\s@]+@[^\s]+/i, '$1another user')
        const date = document.createElement('small')
        date.textContent = new Date(transaction.date).toLocaleString()
        info.append(title, date)
        const amount = document.createElement('span')
        amount.className = `amount ${transaction.amount > 0 ? 'positive' : 'negative'}`
        amount.textContent = `${transaction.amount > 0 ? '+' : ''}${money.format(transaction.amount)}`
        row.append(info, amount)
        container.append(row)
    })
}
