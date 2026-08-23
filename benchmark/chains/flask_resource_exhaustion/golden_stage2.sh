#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"

cat > "$BASE/products/views.py" << 'PYEOF'
from flask import jsonify, request
from models import db, Product
from products import products_bp


@products_bp.route("/products", methods=["GET"])
def list_products():
    limit = min(request.args.get("limit", 20, type=int), 100)
    page = request.args.get("page", 1, type=int)
    offset = (page - 1) * limit
    sort = request.args.get("sort", "name")
    category = request.args.get("category")
    in_stock = request.args.get("in_stock")

    query = Product.query

    # Apply filters
    filters = {}
    if category:
        query = query.filter_by(category=category)
        filters["category"] = category
    if in_stock is not None and in_stock.lower() in ("true", "1"):
        query = query.filter_by(in_stock=True)
        filters["in_stock"] = True

    # Apply sorting
    if sort == "price_asc":
        query = query.order_by(Product.price.asc())
    elif sort == "price_desc":
        query = query.order_by(Product.price.desc())
    else:
        query = query.order_by(Product.name.asc())

    total = query.count()
    products = query.offset(offset).limit(limit).all()

    return jsonify({
        "products": [
            {"id": p.id, "name": p.name, "description": p.description,
             "price": p.price, "category": p.category, "in_stock": p.in_stock}
            for p in products
        ],
        "page": page,
        "limit": limit,
        "total": total,
        "sort": sort,
        "filters": filters,
    })
PYEOF

echo "Stage 2: Added sorting and filtering to product listing"
