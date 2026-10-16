// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

use qdrant_edge::{
    Condition, Distance, EdgeConfigBuilder, EdgeShard, EdgeVectorParamsBuilder, Filter,
    HasIdCondition, NamedQuery, PointId, PointInsertOperations, PointOperations,
    PointStructPersisted, QueryEnum, QueryRequestBuilder, ScoringQuery, UpdateOperation,
    VectorStructInternal, VectorStructPersisted,
};

fn point(id: u64, vector: Vec<f32>) -> PointStructPersisted {
    PointStructPersisted {
        id: PointId::NumId(id),
        vector: VectorStructPersisted::from(VectorStructInternal::Single(vector)),
        payload: None,
    }
}

fn nearest(
    shard: &EdgeShard,
    filter: Option<Filter>,
) -> Result<Vec<qdrant_edge::ScoredPoint>, Box<dyn std::error::Error>> {
    let mut request =
        QueryRequestBuilder::new(2).query(ScoringQuery::Vector(QueryEnum::Nearest(NamedQuery {
            using: None,
            query: vec![1.0, 0.0, 0.0].into(),
        })));
    if let Some(filter) = filter {
        request = request.filter(filter);
    }
    Ok(shard.query(request.build())?)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let directory = tempfile::tempdir()?;
    let config = EdgeConfigBuilder::new()
        .vector(
            "",
            EdgeVectorParamsBuilder::new(3, Distance::Cosine).build(),
        )
        .build();
    let shard = EdgeShard::new(directory.path(), config)?;
    shard.update(UpdateOperation::PointOperation(
        PointOperations::UpsertPoints(PointInsertOperations::PointsList(vec![
            point(1, vec![1.0, 0.0, 0.0]),
            point(2, vec![0.0, 1.0, 0.0]),
        ])),
    ))?;
    assert_eq!(nearest(&shard, None)?[0].id, PointId::NumId(1));
    let filtered = nearest(
        &shard,
        Some(Filter {
            must: Some(vec![Condition::HasId(HasIdCondition {
                has_id: [PointId::NumId(2)].into_iter().collect(),
            })]),
            ..Default::default()
        }),
    )?;
    assert_eq!(filtered.len(), 1);
    assert_eq!(filtered[0].id, PointId::NumId(2));
    assert!(
        shard
            .update(UpdateOperation::PointOperation(
                PointOperations::UpsertPoints(PointInsertOperations::PointsList(vec![point(
                    3,
                    vec![1.0, 0.0]
                )]),)
            ))
            .is_err(),
        "wrong vector dimensions must be rejected"
    );
    shard.flush()?;
    drop(shard);
    let reopened = EdgeShard::load(directory.path(), None)?;
    assert_eq!(nearest(&reopened, None)?[0].id, PointId::NumId(1));
    reopened.update(UpdateOperation::PointOperation(
        PointOperations::DeletePoints {
            ids: vec![PointId::NumId(1)],
        },
    ))?;
    assert_eq!(nearest(&reopened, None)?[0].id, PointId::NumId(2));
    reopened.flush()?;
    println!(
        "PASS: native Qdrant Edge insert/search/filter/dimension rejection/flush/reopen/delete."
    );
    Ok(())
}
